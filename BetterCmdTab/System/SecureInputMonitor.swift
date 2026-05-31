import Carbon.HIToolbox
import Foundation

/// Polls `IsSecureEventInputEnabled()` so the app can react when another process
/// grabs Secure Event Input (a focused password field), which makes the CGEvent
/// tap go deaf. There is no notification for the secure-input state, so a poll is
/// the only option. Modeled on `AccessibilityWaiter`: a cheap, low-frequency
/// main-thread timer that runs for the app's lifetime.
///
/// `IsSecureEventInputEnabled()` is a local HIToolbox call (no XPC), so a 1 s
/// cadence is effectively free while still catching a transition within a second.
final class SecureInputMonitor {
    /// Fired on every transition with the new state. Set before `start()`.
    var onChange: (Bool) -> Void = { _ in }

    private(set) var isActive = false
    private var timer: Timer?

    func start() {
        isActive = IsSecureEventInputEnabled()
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Force an out-of-band check — e.g. the instant a Carbon chord fires while
    /// we believed secure input was off (a Carbon chord firing at all is itself
    /// evidence the tap was bypassed). Shrinks the poll-gap window.
    @discardableResult
    func refresh() -> Bool {
        poll()
        return isActive
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = IsSecureEventInputEnabled()
        guard now != isActive else { return }
        isActive = now
        onChange(now)
    }
}
