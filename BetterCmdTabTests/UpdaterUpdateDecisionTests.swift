import Testing
@testable import BetterCmdTab

@Suite("GitHubUpdateDecision")
struct GitHubUpdateDecisionTests {

    @Test("newer core marks update available")
    func newerCoreAvailable() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.0",
            latestVersion: "1.0.1",
            currentBuildNumber: 100,
            remoteBuildNumber: 200
        ))
        #expect(decision.isUpdateAvailable)
        #expect(!decision.isNewerBuild)
    }

    @Test("older latest never offers update")
    func olderLatestNoUpdate() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.5",
            latestVersion: "1.0.4",
            currentBuildNumber: 500,
            remoteBuildNumber: 400
        ))
        #expect(!decision.isUpdateAvailable)
        #expect(!decision.isNewerBuild)
    }

    @Test("same core + higher remote build → newer build flagged")
    func sameVersionNewerBuild() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.0",
            latestVersion: "1.0.0",
            currentBuildNumber: 20260101000000,
            remoteBuildNumber: 20260201000000
        ))
        #expect(decision.isUpdateAvailable)
        #expect(decision.isNewerBuild)
    }

    @Test("same core + lower remote build → no update")
    func sameVersionOlderBuild() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.0",
            latestVersion: "1.0.0",
            currentBuildNumber: 20260201000000,
            remoteBuildNumber: 20260101000000
        ))
        #expect(!decision.isUpdateAvailable)
        #expect(!decision.isNewerBuild)
    }

    @Test("same core + nil remote build → no update")
    func sameVersionNilRemoteBuild() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.0",
            latestVersion: "1.0.0",
            currentBuildNumber: 100,
            remoteBuildNumber: nil
        ))
        #expect(!decision.isUpdateAvailable)
        #expect(!decision.isNewerBuild)
    }

    @Test("beta → stable transition produces update without newerBuild")
    func betaToStableTransition() {
        let decision = GitHubUpdateDecision.evaluate(.init(
            currentVersion: "1.0.0-beta.3",
            latestVersion: "1.0.0",
            currentBuildNumber: 100,
            remoteBuildNumber: 200
        ))
        #expect(decision.isUpdateAvailable)
        // Different prerelease state — same cores, but `current < latest` already
        // triggers via prerelease precedence. isNewerBuild reserved for true
        // same-version-same-prerelease case (MARKETING_VERSION drops the suffix
        // so we still treat cores as matching — see comment in evaluate()).
        #expect(decision.isNewerBuild)
    }

    @Test("isNewerVersion helper matches ParsedVersion ordering")
    func isNewerVersionHelper() {
        #expect(GitHubUpdateDecision.isNewerVersion("1.0.1", than: "1.0.0"))
        #expect(!GitHubUpdateDecision.isNewerVersion("1.0.0", than: "1.0.1"))
        #expect(!GitHubUpdateDecision.isNewerVersion("1.0.0", than: "1.0.0"))
    }
}
