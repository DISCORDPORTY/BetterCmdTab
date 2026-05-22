import AppKit
import ApplicationServices

enum Activator {
    private static let finderBundleID = "com.apple.finder"

    static func activateApp(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.1)
        var windowsValue: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        let windows = (windowsValue as? [AXUIElement]) ?? []
        if windows.isEmpty {
            openFreshWindow(for: app)
            return
        }
        for window in windows {
            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            if (minimizedValue as? Bool) == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                break
            }
        }
        bringToFront(app)
    }

    static func activate(_ row: SwitcherRow) {
        let app = row.app

        if app.isHidden {
            app.unhide()
        }

        guard let window = row.window else {
            if row.isFullscreen {
                bringToFront(app)
            } else {
                openFreshWindow(for: app)
            }
            return
        }

        var minimizedValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        if (minimizedValue as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        // Non-AppKit windowing (Ghostty/Alacritty/Wezterm and similar
        // GPU-rendered apps) won't receive keyboard focus from
        // NSRunningApplication.activate() alone — they listen for AX main/
        // focused attribute changes. Set both before raise so the app's own
        // focus dispatch fires when activation lands.
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Cross-Space raise: kAXRaiseAction + NSRunningApplication.activate()
        // cannot move the user to a fullscreen Space that hosts only the target
        // window. SkyLight's private SLPS path handles that.
        let wid = PrivateAPI.cgWindowId(of: window)
        if wid != 0 {
            PrivateAPI.raiseWindow(pid: row.pid, wid: wid)
        }
        bringToFront(app)

        // After the app process is frontmost, re-assert focus on the target
        // window. Some apps reset focused window during activation handshake;
        // a second focused/main write inside the app's run loop pins it.
        let pid = row.pid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.1)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func bringToFront(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
            return
        }
        if #available(macOS 14.0, *) {
            _ = app.activate(from: NSRunningApplication.current, options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func openFreshWindow(for app: NSRunningApplication) {
        if app.bundleIdentifier == finderBundleID {
            openNewFinderWindow()
            bringToFront(app)
            return
        }
        guard let url = app.bundleURL else {
            bringToFront(app)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    private static func openNewFinderWindow() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([home], withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: config) { _, _ in }
    }

    static func closeWindow(_ row: SwitcherRow) {
        let window = row.window
        let pid = row.pid
        let isFullscreen = row.isFullscreen

        DispatchQueue.global(qos: .userInitiated).async {
            guard let window else { return }

            if isFullscreen {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                let wid = PrivateAPI.cgWindowId(of: window)
                if wid != 0 {
                    PrivateAPI.raiseWindow(pid: pid, wid: wid)
                }
                Thread.sleep(forTimeInterval: 0.6)
                postKeyShortcut(pid: pid, keyCode: 13, axModifiers: 0)
                return
            }

            pressCloseButton(window: window, attempts: 3)
        }
    }

    private static func pressCloseButton(window: AXUIElement, attempts: Int) {
        for i in 0..<attempts {
            var buttonValue: AnyObject?
            let err = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &buttonValue)
            if err == .success, CFGetTypeID(buttonValue as CFTypeRef) == AXUIElementGetTypeID() {
                let button = buttonValue as! AXUIElement
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                return
            }
            if i < attempts - 1 {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }
    }

    static func minimizeWindow(_ row: SwitcherRow) {
        guard let window = row.window else { return }
        let wasMinimized = row.isMinimized
        let app = row.app
        DispatchQueue.global(qos: .userInitiated).async {
            if wasMinimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                DispatchQueue.main.async {
                    if #available(macOS 14.0, *) {
                        _ = app.activate(from: NSRunningApplication.current, options: [])
                    } else {
                        app.activate(options: [.activateIgnoringOtherApps])
                    }
                }
                return
            }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func postKeyShortcut(pid: pid_t, keyCode: CGKeyCode, axModifiers: Int) {
        let src = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }

        var flags: CGEventFlags = []
        if (axModifiers & 8) == 0 { flags.insert(.maskCommand) }
        if (axModifiers & 1) != 0 { flags.insert(.maskShift) }
        if (axModifiers & 2) != 0 { flags.insert(.maskAlternate) }
        if (axModifiers & 4) != 0 { flags.insert(.maskControl) }

        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }

    static func hideApp(_ row: SwitcherRow) {
        if row.app.isHidden {
            row.app.unhide()
            if #available(macOS 14.0, *) {
                _ = row.app.activate(from: NSRunningApplication.current, options: [])
            } else {
                row.app.activate(options: [.activateIgnoringOtherApps])
            }
        } else {
            row.app.hide()
        }
    }

    static func quitApp(_ row: SwitcherRow) {
        if row.app.bundleIdentifier == finderBundleID {
            return
        }
        row.app.terminate()
    }
}
