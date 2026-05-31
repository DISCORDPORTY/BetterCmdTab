import Darwin
import Foundation

/// Best-effort restoration of the WindowServer symbolic hotkeys (⌘Tab, ⌘⇧Tab,
/// ⌘`) that we disable at runtime via `PrivateAPI.setSymbolicHotKey`.
///
/// That disable **persists after the process dies** (see `PrivateAPI`), so if we
/// crash or are signalled before `SwitcherController.shutdown()` runs, the user's
/// native ⌘Tab stays dead system-wide until reboot or our next launch. This
/// installs signal + `atexit` handlers that re-enable whatever we last disabled.
///
/// SIGKILL and a hard power loss cannot be caught — those are covered by the
/// unconditional startup self-heal in `SwitcherController.start()`, which clears
/// any stale disable on the next launch.
///
/// Restore contract by context:
/// - **Clean exit** (`exit`/return from `main`): the `atexit` hook runs in a
///   normal thread context and performs the WindowServer IPC to re-enable the
///   keys synchronously — ⌘Tab is live again immediately.
/// - **In-session signal** (SIGTERM/SIGINT/SIGHUP, e.g. `kill -TERM`): the
///   handler does **not** call back into the WindowServer. That IPC
///   (`CGSSetSymbolicHotKeyEnabled` → synchronous mach/XPC to the WindowServer)
///   is not async-signal-safe: if the signal interrupts a thread holding a CGS
///   lock or mid-allocation, the in-handler IPC can deadlock the quit path. So
///   the handler only re-raises with the default disposition (`SA_RESETHAND`)
///   to let termination proceed. The disabled set was already persisted to
///   UserDefaults on every change (`persistDisabledSymbolicKeys`), so native
///   ⌘Tab is re-enabled by the unconditional `healStaleSymbolicHotkeyDisable()`
///   on the next launch — not in the handler.
/// - **Crash** (SIGSEGV/SIGBUS/...) and **SIGKILL**/power loss: not caught at
///   all; healed by the same next-launch self-heal.
///
/// Because this is a launch-at-login menu-bar app, "next launch" is normally
/// imminent. The trade-off is that a `kill -TERM` (or any in-session signal)
/// leaves native ⌘Tab disabled until that next launch rather than restoring it
/// in the handler.
enum SymbolicHotkeyGuard {
    /// Max managed keys: ⌘Tab, ⌘⇧Tab, ⌘`. A `0` slot means "empty".
    private static let capacity = 3

    /// Pre-allocated, never freed: the signal handler reads these slots without
    /// allocating. Initialized to all-zero.
    private static let slots: UnsafeMutablePointer<Int32> = {
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
        p.initialize(repeating: 0, count: capacity)
        return p
    }()

    // dlsym'd `CGSSetSymbolicHotKeyEnabled` — resolved once up front so the
    // signal handler only does a plain C call (no dlopen/dlsym in-handler).
    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Int32
    private static let setEnabledFn: SetEnabledFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(h, "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: SetEnabledFn.self)
    }()

    private static var installed = false

    /// Record the raw symbolic-hotkey ids currently disabled, so the signal /
    /// atexit handlers know what to restore. Call on every change to the
    /// disabled set (disable *and* the empty set on clean re-enable).
    ///
    /// A signal arriving mid-write can read a torn set, but each slot is a
    /// word-sized store (atomic on arm64/x86-64) and the consequence is benign:
    /// a missed slot just stays disabled until the next-launch self-heal, and a
    /// stale slot re-enables an already-enabled key (a no-op).
    static func setDisabled(_ rawIds: [Int32]) {
        for i in 0..<capacity {
            slots[i] = i < rawIds.count ? rawIds[i] : 0
        }
    }

    /// Re-enable every recorded slot via the WindowServer IPC. **Normal context
    /// only** — this is the `atexit` path. It is *not* async-signal-safe (the IPC
    /// can block on a CGS lock) and must never be called from a signal handler;
    /// signal-context restoration is delegated to the next-launch self-heal.
    private static func restore() {
        guard let fn = setEnabledFn else { return }
        for i in 0..<capacity where slots[i] != 0 {
            _ = fn(slots[i], true)
        }
    }

    /// Install the signal + `atexit` handlers once. Idempotent. Call early in
    /// app startup, before any symbolic hotkey gets disabled.
    static func install() {
        guard !installed else { return }
        installed = true
        // Force lazy init of the buffer + function pointer now, off the handler
        // path — neither may safely initialize inside a signal handler.
        _ = slots
        _ = setEnabledFn

        atexit { SymbolicHotkeyGuard.restore() }

        // Graceful terminations only. SA_RESETHAND restores the default
        // disposition before the handler runs, so the trailing `raise` performs
        // the normal action (terminate) — without it the signal would be
        // swallowed and the process would keep running.
        // The handler does the minimum async-signal-safe work: re-raise so the
        // (now-default, thanks to SA_RESETHAND) disposition terminates the
        // process. It deliberately does NOT call `restore()` — that IPC is not
        // async-signal-safe; in-session signal cases rely on the next-launch
        // `healStaleSymbolicHotkeyDisable()` instead.
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { sig in
            raise(sig)
        }
        sigemptyset(&action.sa_mask)
        action.sa_flags = SA_RESETHAND
        for s in [SIGTERM, SIGINT, SIGHUP] {
            sigaction(s, &action, nil)
        }
    }
}
