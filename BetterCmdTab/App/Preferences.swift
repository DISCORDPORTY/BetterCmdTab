import Foundation
import Combine

enum SwitcherLayoutMode: String, CaseIterable {
    case list
    case gridView = "iconDock"

    var displayName: String {
        switch self {
        case .list: return "List"
        case .gridView: return "Grid View"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Keys {
        static let switcherLayoutMode = "Switcher.layoutMode"
    }

    @Published var switcherLayoutMode: SwitcherLayoutMode {
        didSet {
            guard oldValue != switcherLayoutMode else { return }
            UserDefaults.standard.set(switcherLayoutMode.rawValue, forKey: Keys.switcherLayoutMode)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.switcherLayoutMode)
        self.switcherLayoutMode = raw.flatMap(SwitcherLayoutMode.init(rawValue:)) ?? .gridView
    }
}
