import Testing
@testable import BetterCmdTab

@Suite("ParsedVersion")
struct ParsedVersionTests {

    @Test("strips leading v prefix")
    func stripsVPrefix() {
        #expect(ParsedVersion("v1.2.3") == ParsedVersion("1.2.3"))
    }

    @Test("core components compare numerically not lexically")
    func numericCoreCompare() {
        #expect(ParsedVersion("1.2.10") > ParsedVersion("1.2.9"))
        #expect(ParsedVersion("1.10.0") > ParsedVersion("1.9.99"))
        #expect(ParsedVersion("2.0.0") > ParsedVersion("1.99.99"))
    }

    @Test("missing components default to zero in ordering")
    func paddedComponents() {
        // Equatable compares stored `core` arrays directly so "1.0" ≠ "1.0.0";
        // ordering is the contract this test pins.
        #expect(!(ParsedVersion("1.0") < ParsedVersion("1.0.0")))
        #expect(!(ParsedVersion("1.0.0") < ParsedVersion("1.0")))
        #expect(ParsedVersion("1") < ParsedVersion("1.0.1"))
        #expect(ParsedVersion("1") < ParsedVersion("1.1"))
    }

    @Test("prerelease has lower precedence than stable")
    func prereleaseLowerThanStable() {
        #expect(ParsedVersion("1.0.0-beta.1") < ParsedVersion("1.0.0"))
        #expect(ParsedVersion("1.0.0-alpha") < ParsedVersion("1.0.0"))
    }

    @Test("two stables of same core are equal")
    func equalStables() {
        #expect(!(ParsedVersion("1.0.0") < ParsedVersion("1.0.0")))
        #expect(ParsedVersion("1.0.0") == ParsedVersion("1.0.0"))
    }

    @Test("numeric prerelease identifiers compare numerically")
    func numericPrereleaseCompare() {
        #expect(ParsedVersion("1.0.0-beta.2") < ParsedVersion("1.0.0-beta.10"))
        #expect(ParsedVersion("1.0.0-beta.9") < ParsedVersion("1.0.0-beta.11"))
    }

    @Test("alpha-prerelease orders before beta-prerelease")
    func alphaBeforeBeta() {
        #expect(ParsedVersion("1.0.0-alpha") < ParsedVersion("1.0.0-beta"))
        #expect(ParsedVersion("1.0.0-beta") > ParsedVersion("1.0.0-alpha.99"))
    }

    @Test("shorter prerelease ordered before longer when prefix identical")
    func shorterPrereleaseFirst() {
        #expect(ParsedVersion("1.0.0-beta") < ParsedVersion("1.0.0-beta.1"))
    }

    @Test("major bump wins regardless of prerelease state")
    func majorBumpOverPrerelease() {
        #expect(ParsedVersion("1.0.0") < ParsedVersion("2.0.0-alpha"))
    }
}
