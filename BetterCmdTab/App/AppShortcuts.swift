import AppKit
import BetterShortcuts

// Strongly-typed names for BetterCmdTab's two switcher triggers. The recorded
// shortcuts are stored by the BetterShortcuts package but are NOT registered
// as live Carbon hotkeys — no `onKeyDown`/`onKeyUp` handler is attached, so the
// package never steals the combo. The CGEvent tap in `HotkeyTap` remains the
// runtime engine; it reads the stored shortcut and decomposes it into a held
// modifier + tap key (see `SwitcherController.pushHotkeyConfig`).
extension BetterShortcuts.Name {
    static let switchApps = Self("switchApps", default: .init(.tab, modifiers: .command))
    static let switchWindows = Self("switchWindows", default: .init(.backtick, modifiers: .command))
}

extension BetterShortcuts.Name: @retroactive CaseIterable {
    public static var allCases: [Self] { [.switchApps, .switchWindows] }

    /// Human-readable label used by the recorder's conflict alert.
    var displayName: String {
        switch self {
        case .switchApps: return "Switch apps"
        case .switchWindows: return "Switch windows"
        default: return rawValue
        }
    }
}

extension BetterShortcuts {
    /// Wire the package's conflict-alert label provider to our `displayName`s. Call once at launch.
    static func installDisplayNames() {
        BetterShortcuts.displayName = { $0.displayName }
    }
}
