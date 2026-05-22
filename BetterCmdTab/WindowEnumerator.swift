import AppKit
import ApplicationServices

struct WindowInfo {
    let ref: AXUIElement
    let title: String
    let isMinimized: Bool
}

enum WindowEnumerator {
    static func windows(forPid pid: pid_t) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.2)

        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let axWindows = windowsValue as? [AXUIElement] else {
            return []
        }

        var infos: [WindowInfo] = []
        infos.reserveCapacity(axWindows.count)

        for window in axWindows {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
            let role = (roleValue as? String) ?? ""
            if !role.isEmpty && role != kAXWindowRole {
                continue
            }

            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""

            let skippedSubroles: Set<String> = [
                kAXSystemDialogSubrole,
                kAXSystemFloatingWindowSubrole,
            ]
            if skippedSubroles.contains(subrole) {
                continue
            }

            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String) ?? ""

            infos.append(WindowInfo(ref: window, title: title, isMinimized: minimized))
        }

        return infos
    }
}
