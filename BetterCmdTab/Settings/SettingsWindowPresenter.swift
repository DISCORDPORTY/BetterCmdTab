import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {

    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        if !window.isVisible {
            window.center()
        }
        window.orderFrontRegardless()

        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
        restoreActivationPolicyIfNeeded()
    }

    private func createWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.delegate = SettingsWindowDelegate.shared
        self.window = window
    }

    fileprivate func windowWillClose() {
        restoreActivationPolicyIfNeeded()
    }

    private func restoreActivationPolicyIfNeeded() {
        let hasOtherVisibleWindow = NSApp.windows.contains { w in
            w !== window && w.isVisible && !(w is NSPanel)
        }
        if !hasOtherVisibleWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        SettingsWindowPresenter.shared.windowWillClose()
    }
}
