import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SwitcherController?
    private var statusItem: NSStatusItem?
    private var axWaiter: AccessibilityWaiter?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let waiter = AccessibilityWaiter()
        waiter.onTrusted = { [weak self] in
            self?.bootController()
        }
        waiter.start()
        axWaiter = waiter
    }

    private func bootController() {
        guard controller == nil else { return }
        let c = SwitcherController()
        c.start()
        controller = c
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "BetterCmdTab")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit BetterCmdTab", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
