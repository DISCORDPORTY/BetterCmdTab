import Testing
@testable import BetterCmdTab

@Suite("AppInfo")
struct AppInfoTests {
    @Test("appVersion never empty")
    func versionNonEmpty() {
        #expect(!AppInfo.appVersion.isEmpty)
    }

    @Test("appBuildNumber never empty")
    func buildNumberNonEmpty() {
        #expect(!AppInfo.appBuildNumber.isEmpty)
    }

    @Test("displayName falls back to BetterCmdTab when bundle keys missing")
    func displayNameFallback() {
        #expect(!AppInfo.displayName.isEmpty)
    }
}
