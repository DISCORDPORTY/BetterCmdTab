import CoreGraphics
import Foundation

/// Detects release of the hold modifier (⌘ by default) while the switcher panel
/// is open under Secure Event Input.
///
/// Under Secure Event Input the CGEvent tap is deaf, so the normal
/// `flagsChanged`-driven commit-on-release never fires; and the Carbon survivor
/// trigger (`RegisterEventHotKey`) only emits *key-pressed*, never a modifier
/// release. The one signal left is the global modifier *state*: Secure Event
/// Input withholds event *delivery* (TN2150), not state *queries*, so
/// `CGEventSource.flagsState` keeps reflecting the physical modifier. We poll it
/// on a short timer, but only while it actually matters (panel open + secure
/// input), so the normal path pays nothing.
///
/// The decision is pure (`modifierReleased` / `holdState`); only the timer and
/// the state read are impure, which keeps the commit-on-release logic testable.
/// Modeled on `SecureInputMonitor`: a plain main-thread timer (it is started and
/// torn down from the main actor).
final class HoldModifierMonitor {
    /// Fired when the hold modifier transitions held → released.
    var onRelease: () -> Void = {}
    /// Fired on any held ↔ released transition with the new state, so the caller
    /// can re-sync which secure-input Carbon chords are registered.
    var onHoldChange: (Bool) -> Void = { _ in }

    private(set) var isHeld = false
    private var mask: CGEventFlags = .maskCommand
    private var timer: Timer?

    /// Pure: did the modifier go from held to released?
    static func modifierReleased(previous: Bool, current: Bool) -> Bool {
        previous && !current
    }

    /// Pure: is every bit of `mask` currently down in `flags`?
    static func holdState(flags: CGEventFlags, mask: CGEventFlags) -> Bool {
        flags.contains(mask)
    }

    /// Begin polling for the given hold modifier. `assumeHeld` seeds the state so
    /// a panel opened by a held trigger is treated as held immediately — a
    /// switching Carbon chord firing *proves* the modifier is down — independent
    /// of whether the state query happens to work under Secure Event Input on
    /// this OS. Idempotent: a second `start` only updates the mask/seed.
    func start(mask: CGEventFlags, assumeHeld: Bool) {
        self.mask = mask
        isHeld = assumeHeld
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isHeld = false
    }

    private func currentlyHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return Self.holdState(flags: flags, mask: mask)
    }

    private func poll() {
        let now = currentlyHeld()
        guard now != isHeld else { return }
        let wasHeld = isHeld
        isHeld = now
        onHoldChange(now)
        if Self.modifierReleased(previous: wasHeld, current: now) {
            onRelease()
        }
    }
}
