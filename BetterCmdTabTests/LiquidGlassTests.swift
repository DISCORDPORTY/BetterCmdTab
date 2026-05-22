import Testing
@testable import BetterCmdTab

@Suite("LiquidGlassVariant raw values")
struct LiquidGlassVariantTests {

    /// Raw values are passed to `_variant` on NSGlassEffectView via setValue(forKey:).
    /// Changing them silently breaks glass rendering on macOS 26+. Pin them.
    @Test("variant raw values stable")
    func rawValuesStable() {
        #expect(LiquidGlassVariant.regular.rawValue == 0)
        #expect(LiquidGlassVariant.clear.rawValue == 1)
        #expect(LiquidGlassVariant.dock.rawValue == 2)
        #expect(LiquidGlassVariant.sidebar.rawValue == 16)
        #expect(LiquidGlassVariant.control.rawValue == 19)
    }

    @Test("ScrimState raw values stable")
    func scrimRaw() {
        #expect(ScrimState.off.rawValue == 0)
        #expect(ScrimState.on.rawValue == 1)
    }

    @Test("SubduedState raw values stable")
    func subduedRaw() {
        #expect(SubduedState.normal.rawValue == 0)
        #expect(SubduedState.subdued.rawValue == 1)
    }

    @Test("all variant cases enumerate")
    func allCasesEnumerable() {
        // CaseIterable conformance — protect against accidental case removal.
        #expect(LiquidGlassVariant.allCases.count >= 24)
    }
}
