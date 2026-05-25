import AppKit

/// Experimental: detects a horizontal multi-finger trackpad swipe and reports a
/// direction so the switcher can be opened/advanced without the keyboard.
///
/// Uses a global `.swipe` event monitor — public API, no private frameworks —
/// which means it cannot *consume* the gesture, so the system may also act on
/// it (Mission Control / page navigation, depending on the user's trackpad
/// settings). That's why the feature is off by default and labeled
/// experimental. `.swipe` events are only delivered at all when the trackpad's
/// swipe gesture is enabled in System Settings.
@MainActor
final class SwipeTrigger {
    /// `+1` for a swipe that should advance forward, `-1` for backward.
    var onSwipe: (Int) -> Void = { _ in }

    private var monitor: Any?

    func setEnabled(_ enabled: Bool) {
        if enabled { install() } else { uninstall() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            let dx = event.deltaX
            guard dx != 0 else { return }
            // NSEvent swipe deltaX is inverted relative to finger motion: a
            // positive value is a swipe to the left. Map a leftward swipe to
            // "forward" so it feels like flipping through a stack rightward.
            self?.onSwipe(dx > 0 ? 1 : -1)
        }
    }

    private func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
