import AppKit
import SwiftUI
import Combine

@MainActor
final class UpdateWindowPresenter {

    static let shared = UpdateWindowPresenter()

    private var window: NSWindow?
    private var stateObserver: AnyCancellable?

    private init() {
        observeUpdaterState()
    }

    func show() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        window.center()
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

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Private

    private func createWindow() {
        let hosting = NSHostingController(rootView: UpdateWindowView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Software Update"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.level = .floating
        self.window = window
    }

    private func observeUpdaterState() {
        stateObserver = GitHubUpdater.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle, .upToDate:
                    self.hide()
                default:
                    break
                }
            }
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
