import Foundation
import Testing
@testable import BetterCmdTab

/// Tests for rebindable window-management chords (#7): KeyCombo round-trip, the
/// ⌃-arrow defaults (must stay stable so existing users see no change), and the
/// normalize/load helpers that keep the stored map complete and junk-tolerant.
@MainActor
@Suite("Window management bindings")
struct WindowMgmtBindingTests {

    @Test("defaults are Control + arrow keys")
    func defaults() {
        #expect(WindowMgmtAction.tileLeft.defaultCombo == KeyCombo(keyCode: 123, modifiers: 1))
        #expect(WindowMgmtAction.tileRight.defaultCombo == KeyCombo(keyCode: 124, modifiers: 1))
        #expect(WindowMgmtAction.maximize.defaultCombo == KeyCombo(keyCode: 126, modifiers: 1))
        #expect(WindowMgmtAction.center.defaultCombo == KeyCombo(keyCode: 125, modifiers: 1))
        #expect(WindowMgmtAction.allCases.count == 4)
    }

    @Test("KeyCombo serializes and round-trips")
    func comboRoundTrip() {
        let combo = KeyCombo(keyCode: 38, modifiers: 6) // ⌥⇧J
        #expect(combo.serialized == "38:6")
        #expect(KeyCombo(serialized: "38:6") == combo)
        #expect(KeyCombo(serialized: "garbage") == nil)
        #expect(KeyCombo(serialized: "38") == nil)
    }

    @Test("normalize fills every missing action with its default")
    func normalizeFills() {
        let result = Preferences.normalizeWindowMgmt([.tileLeft: KeyCombo(keyCode: 9, modifiers: 2)])
        #expect(result.count == 4)
        #expect(result[.tileLeft] == KeyCombo(keyCode: 9, modifiers: 2))
        #expect(result[.maximize] == WindowMgmtAction.maximize.defaultCombo)
    }

    @Test("loadWindowMgmt parses raw dict and drops unknown/garbled")
    func loadParses() {
        let result = Preferences.loadWindowMgmt(["tileLeft": "9:2", "bogus": "1:1", "center": "junk"])
        #expect(result[.tileLeft] == KeyCombo(keyCode: 9, modifiers: 2))
        // garbled "center" falls back to default; "bogus" ignored.
        #expect(result[.center] == WindowMgmtAction.center.defaultCombo)
        #expect(result.count == 4)
    }

    @Test("loadWindowMgmt handles nil as all-default")
    func loadNil() {
        let result = Preferences.loadWindowMgmt(nil)
        #expect(result.count == 4)
        for action in WindowMgmtAction.allCases {
            #expect(result[action] == action.defaultCombo)
        }
    }
}
