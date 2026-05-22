import AppKit
import ApplicationServices

struct WindowInfo {
    let ref: AXUIElement
    let title: String
    let isMinimized: Bool
    let isFullscreen: Bool

    init(
        ref: AXUIElement,
        title: String,
        isMinimized: Bool,
        isFullscreen: Bool = false
    ) {
        self.ref = ref
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
    }
}

private struct AXRef: Hashable {
    let element: AXUIElement
    static func == (lhs: AXRef, rhs: AXRef) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum WindowEnumerator {
    private static let bruteForceLimit: UInt64 = 256
    private static let preFilterTimeout: Float = 0.025
    private static let confirmedTimeout: Float = 0.2

    static func windows(forPid pid: pid_t, isRegularApp: Bool = true) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.confirmedTimeout)

        var elements: [AXUIElement] = []
        var seenByElement = Set<AXRef>()
        var seenByWid = Set<CGWindowID>()

        func appendIfNew(_ e: AXUIElement) {
            let ref = AXRef(element: e)
            if seenByElement.contains(ref) { return }
            let wid = PrivateAPI.cgWindowId(of: e)
            if wid != 0 {
                if seenByWid.contains(wid) { return }
                seenByWid.insert(wid)
            }
            seenByElement.insert(ref)
            elements.append(e)
        }

        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            for w in axWindows { appendIfNew(w) }
        }

        // Brute-force scan only for regular (Dock-visible) apps. Accessory apps
        // (menu-bar utilities like Clop, Bartender) often expose ghost AXWindow
        // refs for popovers that the remote-token API returns even when closed.
        if isRegularApp {
            let acceptedSubroles: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
            ]
            for axId: UInt64 in 0..<bruteForceLimit {
                guard let e = PrivateAPI.axElement(pid: pid, axId: axId) else { continue }
                // Fast pre-filter: most axIds are non-window elements. Use tight
                // timeout to skip them quickly. Bump it once role confirmed.
                AXUIElementSetMessagingTimeout(e, Self.preFilterTimeout)

                var elemPid: pid_t = 0
                guard AXUIElementGetPid(e, &elemPid) == .success, elemPid == pid else { continue }

                var roleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &roleValue)
                guard (roleValue as? String) == (kAXWindowRole as String) else { continue }

                AXUIElementSetMessagingTimeout(e, Self.confirmedTimeout)

                var subroleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &subroleValue)
                guard let subrole = subroleValue as? String, acceptedSubroles.contains(subrole) else { continue }

                let wid = PrivateAPI.cgWindowId(of: e)
                guard wid != 0 else { continue }

                var sizeValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeValue)
                if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                    var size = CGSize.zero
                    AXValueGetValue(sv as! AXValue, .cgSize, &size)
                    if size.width < 100 || size.height < 100 { continue }
                } else {
                    continue
                }

                appendIfNew(e)
            }
        }

        var infos: [WindowInfo] = []
        infos.reserveCapacity(elements.count)

        let acceptedSubroles: Set<String> = [
            kAXStandardWindowSubrole as String,
            kAXDialogSubrole as String,
        ]
        // Native macOS tab merging (Safari/Finder/TextEdit) exposes each tab
        // as a separate AXWindow. Siblings share the same kAXTabsAttribute
        // tab-button list. Group windows by that signature and keep one.
        var seenTabGroups: Set<[AXRef]> = []
        for window in elements {
            AXUIElementSetMessagingTimeout(window, Self.confirmedTimeout)
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""
            // Reject popovers, status items, panels, floating UI etc — accept
            // only AXStandardWindow / AXDialog (real Dock-switchable windows).
            guard acceptedSubroles.contains(subrole) else { continue }

            var tabsValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTabsAttribute as CFString, &tabsValue)
            if let tabs = tabsValue as? [AXUIElement], tabs.count > 1 {
                let key = tabs.map { AXRef(element: $0) }
                if seenTabGroups.contains(key) { continue }
                seenTabGroups.insert(key)
            }

            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

            var fullscreenValue: AnyObject?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
            let fullscreen = (fullscreenValue as? Bool) ?? false

            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let windowTitle = (titleValue as? String) ?? ""

            infos.append(WindowInfo(
                ref: window,
                title: windowTitle,
                isMinimized: minimized,
                isFullscreen: fullscreen
            ))
        }

        return infos
    }
}
