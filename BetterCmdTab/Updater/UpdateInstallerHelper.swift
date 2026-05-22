import Foundation
import AppKit
import Security

/// Out-of-process installer helper, equivalent to Sparkle's `Autoupdate`.
///
/// A running `.app` cannot reliably overwrite itself: copying over a mapped
/// bundle, or `mv`'ing the executable while it is in use, fails on macOS.
/// `handoffSwap` writes a small shell script to a private temp directory,
/// spawns it detached, and returns. The script waits for the parent process
/// to exit, swaps the bundle into place, strips the quarantine xattr, and
/// relaunches via `open -n`.
enum UpdateInstallerHelper {

    enum HandoffError: LocalizedError {
        case stageFailed(String)
        case helperWriteFailed(String)
        case spawnFailed(String)
        case authorizationDenied
        case authorizationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .stageFailed(let msg):
                return "Could not stage update: \(msg)"
            case .helperWriteFailed(let msg):
                return "Could not prepare installer helper: \(msg)"
            case .spawnFailed(let msg):
                return "Could not start installer helper: \(msg)"
            case .authorizationDenied:
                return "Authorization was cancelled."
            case .authorizationFailed(let status):
                return "Authorization failed (\(status))."
            }
        }
    }

    /// Hands off bundle replacement to an external script and returns.
    /// Caller MUST terminate this process shortly after; the helper polls
    /// for parent exit before touching the target.
    static func handoffSwap(
        stagedAppURL: URL,
        targetAppURL: URL,
        removeSource: Bool
    ) async throws {
        let parentPID = ProcessInfo.processInfo.processIdentifier
        let helperURL = try writeHelperScript()
        let chownUser = currentUserAndGroup()

        let writable = isWritable(targetAppURL.deletingLastPathComponent())

        let args = helperArguments(
            parentPID: parentPID,
            source: stagedAppURL,
            target: targetAppURL,
            removeSource: removeSource,
            chownUser: writable ? nil : chownUser
        )

        if writable {
            try spawnDetached(helper: helperURL, arguments: args)
        } else {
            try await Task.detached(priority: .userInitiated) {
                try runWithPrivileges(helper: helperURL, arguments: args)
            }.value
        }
    }

    static func isWritable(_ directory: URL) -> Bool {
        access(directory.path, W_OK) == 0
    }

    // MARK: - Helper script

    private static let helperScript: String = #"""
    #!/bin/bash
    # BetterCmdTab update installer helper.
    # Args: <parentPID> <source> <target> <removeSource:0|1> [chownUser]
    set -u
    PARENT_PID="${1:?missing parentPID}"
    SOURCE="${2:?missing source}"
    TARGET="${3:?missing target}"
    REMOVE_SOURCE="${4:-0}"
    CHOWN_USER="${5:-}"
    LOG="${TMPDIR:-/tmp}/BetterCmdTabInstallHelper.log"
    {
        echo "[$(date '+%H:%M:%S')] start pid=$$ uid=$(id -u) parent=$PARENT_PID source=$SOURCE target=$TARGET remove=$REMOVE_SOURCE chown=$CHOWN_USER"

        # Wait for parent (the running BetterCmdTab process) to exit.
        for _ in $(seq 1 600); do
            if ! kill -0 "$PARENT_PID" 2>/dev/null; then break; fi
            sleep 0.2
        done

        if kill -0 "$PARENT_PID" 2>/dev/null; then
            echo "[$(date '+%H:%M:%S')] parent did not exit within 120s, aborting"
            exit 10
        fi

        # Sanity: source must exist before touching target. Without this, a race
        # that deletes the staging dir would back up the live target and then fail
        # to install anything, leaving the user with no app at the target path.
        if [[ ! -d "$SOURCE" ]]; then
            echo "[$(date '+%H:%M:%S')] source bundle missing, aborting before touching target"
            exit 9
        fi

        # Strip quarantine on staged bundle so the installed copy doesn't re-translocate.
        /usr/bin/xattr -dr com.apple.quarantine "$SOURCE" 2>/dev/null || true

        # Backup current target if present, for rollback on failure.
        BACKUP=""
        if [[ -d "$TARGET" ]]; then
            BACKUP="${TARGET%.*}.previous.app"
            /bin/rm -rf "$BACKUP" 2>/dev/null || true
            if ! /bin/mv -f "$TARGET" "$BACKUP"; then
                echo "[$(date '+%H:%M:%S')] failed to move existing target out of the way"
                exit 11
            fi
        fi

        if [[ "$REMOVE_SOURCE" == "1" ]]; then
            if ! /bin/mv -f "$SOURCE" "$TARGET"; then
                echo "[$(date '+%H:%M:%S')] mv failed; attempting copy fallback"
                /usr/bin/ditto "$SOURCE" "$TARGET" || {
                    echo "[$(date '+%H:%M:%S')] ditto failed; restoring backup"
                    [[ -n "$BACKUP" ]] && /bin/mv -f "$BACKUP" "$TARGET"
                    exit 12
                }
                /bin/rm -rf "$SOURCE" 2>/dev/null || true
            fi
        else
            if ! /usr/bin/ditto "$SOURCE" "$TARGET"; then
                echo "[$(date '+%H:%M:%S')] ditto failed; restoring backup"
                [[ -n "$BACKUP" ]] && /bin/mv -f "$BACKUP" "$TARGET"
                exit 13
            fi
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

        if [[ "$(id -u)" == "0" && -n "$CHOWN_USER" ]]; then
            /usr/sbin/chown -R "$CHOWN_USER" "$TARGET" 2>/dev/null || true
        fi

        if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
            /bin/rm -rf "$BACKUP" 2>/dev/null || true
        fi

        if [[ "$(id -u)" == "0" && -n "$CHOWN_USER" ]]; then
            /usr/bin/sudo -u "${CHOWN_USER%%:*}" /usr/bin/open -n "$TARGET" || {
                echo "[$(date '+%H:%M:%S')] open (as user) failed"
                exit 14
            }
        else
            /usr/bin/open -n "$TARGET" || {
                echo "[$(date '+%H:%M:%S')] open failed"
                exit 14
            }
        fi

        echo "[$(date '+%H:%M:%S')] done"
        exit 0
    } >> "$LOG" 2>&1
    """#

    private static func writeHelperScript() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterCmdTab-Installer-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw HandoffError.helperWriteFailed(error.localizedDescription)
        }
        let url = dir.appendingPathComponent("install_helper.sh")
        do {
            try helperScript.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HandoffError.helperWriteFailed(error.localizedDescription)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw HandoffError.helperWriteFailed("chmod failed: \(error.localizedDescription)")
        }
        return url
    }

    private static func helperArguments(
        parentPID: pid_t,
        source: URL,
        target: URL,
        removeSource: Bool,
        chownUser: String?
    ) -> [String] {
        var args = [
            String(parentPID),
            source.path,
            target.path,
            removeSource ? "1" : "0"
        ]
        if let chownUser, !chownUser.isEmpty {
            args.append(chownUser)
        }
        return args
    }

    private static func currentUserAndGroup() -> String {
        let uid = getuid()
        let gid = getgid()
        let user: String
        if let pw = getpwuid(uid), let name = pw.pointee.pw_name {
            user = String(cString: name)
        } else {
            user = String(uid)
        }
        let group: String
        if let gr = getgrgid(gid), let name = gr.pointee.gr_name {
            group = String(cString: name)
        } else {
            group = String(gid)
        }
        return "\(user):\(group)"
    }

    // MARK: - Spawn paths

    private static func spawnDetached(helper: URL, arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [helper.path] + arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.qualityOfService = .userInitiated
        do {
            try task.run()
        } catch {
            throw HandoffError.spawnFailed(error.localizedDescription)
        }
        BCTLog.updater.notice("Spawned installer helper pid=\(task.processIdentifier)")
    }

    /// Runs the helper with admin privileges via `AuthorizationExecuteWithPrivileges`.
    /// Deprecated API but still functional on macOS 15. Falls back from spawnDetached
    /// when the target parent directory is not writable.
    private static func runWithPrivileges(helper: URL, arguments: [String]) throws {
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [.interactionAllowed], &authRef)
        guard authStatus == errAuthorizationSuccess, let authRef else {
            throw HandoffError.authorizationFailed(authStatus)
        }
        defer { AuthorizationFree(authRef, [.destroyRights]) }

        let rightName = kAuthorizationRightExecute
        let result: OSStatus = rightName.withCString { rightCString in
            var item = AuthorizationItem(name: rightCString, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
                return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
            }
        }

        switch result {
        case errAuthorizationSuccess:
            break
        case errAuthorizationCanceled:
            throw HandoffError.authorizationDenied
        default:
            throw HandoffError.authorizationFailed(result)
        }

        // AuthorizationExecuteWithPrivileges is deprecated but the only API
        // available without bundling a privileged SMJobBless helper. Resolve
        // dynamically to avoid the deprecation warning at compile time.
        typealias ExecFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "AuthorizationExecuteWithPrivileges") else {
            throw HandoffError.spawnFailed("AuthorizationExecuteWithPrivileges unavailable")
        }
        let exec = unsafeBitCast(sym, to: ExecFn.self)

        let cStrings: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer {
            for p in cStrings where p != nil { free(p) }
        }

        let status = helper.path.withCString { pathPtr -> OSStatus in
            cStrings.withUnsafeBufferPointer { argvPtr in
                exec(authRef, pathPtr, [], argvPtr.baseAddress!, nil)
            }
        }

        switch status {
        case errAuthorizationSuccess:
            BCTLog.updater.notice("Privileged installer helper launched")
        case errAuthorizationCanceled:
            throw HandoffError.authorizationDenied
        default:
            throw HandoffError.spawnFailed("AuthorizationExecuteWithPrivileges status=\(status)")
        }
    }
}
