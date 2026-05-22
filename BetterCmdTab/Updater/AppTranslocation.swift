import AppKit
import Foundation
import Security

/// Detects and resolves Gatekeeper Path Randomization (App Translocation).
///
/// When the app is launched from a quarantined location (e.g. `~/Downloads`),
/// macOS runs it from a read-only mount under
/// `/private/var/folders/.../AppTranslocation/<UUID>/d/<App>.app`. Bundle paths
/// inside the running process point at the translocated location, which breaks
/// the in-place self-updater because:
///   - The bundle URL is not under `/Applications`, so the updater targets `/Applications/<App>.app`.
///   - The translocated mount is read-only.
///   - After a manual install, Dock entries and recent items can re-launch the
///     translocated path, so the new build never becomes the running build.
///
/// `guardLaunchLocation()` must run before any update check.
enum AppTranslocation {

    static func isTranslocated() -> Bool {
        let bundleURL = Bundle.main.bundleURL

        if let result = secTranslocateIsTranslocated(bundleURL) {
            return result
        }

        return bundleURL.path.contains("/AppTranslocation/")
    }

    static func originalLocation() -> URL? {
        secTranslocateOriginalURL(Bundle.main.bundleURL)
    }

    @MainActor
    @discardableResult
    static func guardLaunchLocation() -> Bool {
        guard isTranslocated() else { return true }

        BCTLog.updater.notice("App launched from translocated path: \(Bundle.main.bundleURL.path)")

        Task { @MainActor in
            await presentTranslocationAlertAndResolve()
        }
        return false
    }

    @MainActor
    private static func presentTranslocationAlertAndResolve() async {
        let alert = NSAlert()
        alert.messageText = "Move BetterCmdTab to Applications"
        alert.informativeText = "BetterCmdTab is running from a temporary location and cannot install updates from here. Move it to your Applications folder to continue."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            BCTLog.updater.notice("User declined to move translocated app — quitting")
            NSApplication.shared.terminate(nil)
            return
        }

        do {
            try await moveToApplicationsAndRelaunch()
        } catch {
            BCTLog.updater.error("Failed to move translocated app: \(error.localizedDescription)")
            let failure = NSAlert()
            failure.messageText = "Could Not Move BetterCmdTab"
            failure.informativeText = "Please drag BetterCmdTab to your Applications folder manually, then relaunch.\n\n\(error.localizedDescription)"
            failure.alertStyle = .critical
            failure.addButton(withTitle: "Quit")
            failure.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    @MainActor
    static func moveToApplicationsAndRelaunch() async throws {
        let sourceURL = originalLocation() ?? Bundle.main.bundleURL
        let bundleName = Bundle.main.bundleURL.lastPathComponent
        let targetURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleName)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            BCTLog.updater.notice("Found existing \(targetURL.path) — relaunching from there instead of copying \(sourceURL.path)")
            try relaunchExisting(at: targetURL)
            return
        }

        BCTLog.updater.notice("Moving \(sourceURL.path) → \(targetURL.path)")

        try await UpdateInstallerHelper.handoffSwap(
            stagedAppURL: sourceURL,
            targetAppURL: targetURL,
            removeSource: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    @MainActor
    private static func relaunchExisting(at targetURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", targetURL.path]
        try task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - SecTranslocate dynamic linkage

    private typealias IsTranslocatedFn = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
    private typealias CreateOriginalPathFn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    nonisolated(unsafe) private static let securityHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)
    }()

    private static func secTranslocateIsTranslocated(_ url: URL) -> Bool? {
        guard let handle = securityHandle,
              let sym = dlsym(handle, "SecTranslocateIsTranslocatedURL") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: IsTranslocatedFn.self)
        var result: DarwinBoolean = false
        var errPtr: Unmanaged<CFError>? = nil
        let ok = fn(url as CFURL, &result, &errPtr)
        if let err = errPtr {
            err.release()
        }
        guard ok.boolValue else { return nil }
        return result.boolValue
    }

    private static func secTranslocateOriginalURL(_ url: URL) -> URL? {
        guard let handle = securityHandle,
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: CreateOriginalPathFn.self)
        var errPtr: Unmanaged<CFError>? = nil
        guard let cfURLUnmanaged = fn(url as CFURL, &errPtr) else {
            if let err = errPtr {
                err.release()
            }
            return nil
        }
        let cfURL = cfURLUnmanaged.takeRetainedValue()
        return cfURL as URL
    }
}
