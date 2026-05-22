import Foundation
import Testing
@testable import BetterCmdTab

@Suite("UpdateState equality")
struct UpdateStateEqualityTests {

    @Test("idempotent simple cases")
    func simpleCases() {
        #expect(UpdateState.idle == UpdateState.idle)
        #expect(UpdateState.checking == UpdateState.checking)
        #expect(UpdateState.upToDate == UpdateState.upToDate)
    }

    @Test("available equal iff version + notes match")
    func availableMatch() {
        let a = UpdateState.available(version: "1.0.0", releaseNotes: "x")
        let b = UpdateState.available(version: "1.0.0", releaseNotes: "x")
        let c = UpdateState.available(version: "1.0.0", releaseNotes: "y")
        let d = UpdateState.available(version: "1.0.1", releaseNotes: "x")
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("downloading equal by progress")
    func downloadingMatch() {
        #expect(UpdateState.downloading(progress: 0.5) == .downloading(progress: 0.5))
        #expect(UpdateState.downloading(progress: 0.5) != .downloading(progress: 0.6))
    }

    @Test("installing equal by progress + step")
    func installingMatch() {
        #expect(UpdateState.installing(progress: 0.1, step: "x") == .installing(progress: 0.1, step: "x"))
        #expect(UpdateState.installing(progress: 0.1, step: "x") != .installing(progress: 0.1, step: "y"))
    }

    @Test("readyToInstall equal by URL")
    func readyMatch() {
        let url1 = URL(fileURLWithPath: "/tmp/a.dmg")
        let url2 = URL(fileURLWithPath: "/tmp/a.dmg")
        let url3 = URL(fileURLWithPath: "/tmp/b.dmg")
        #expect(UpdateState.readyToInstall(localURL: url1) == .readyToInstall(localURL: url2))
        #expect(UpdateState.readyToInstall(localURL: url1) != .readyToInstall(localURL: url3))
    }

    @Test("error equal by message")
    func errorMatch() {
        #expect(UpdateState.error("x") == .error("x"))
        #expect(UpdateState.error("x") != .error("y"))
    }

    @Test("different cases never equal")
    func differentCases() {
        #expect(UpdateState.idle != .checking)
        #expect(UpdateState.idle != .upToDate)
        #expect(UpdateState.checking != .upToDate)
    }
}

@Suite("UpdateError descriptions")
struct UpdateErrorTests {
    @Test("each case carries a non-empty localizedDescription")
    func descriptionsNonEmpty() {
        let cases: [UpdateError] = [
            .networkError("offline"),
            .invalidResponse,
            .noReleasesFound,
            .parsingError("bad json"),
            .downloadFailed("timeout"),
            .installationFailed("mv failed"),
            .userCancelled
        ]
        for e in cases {
            #expect(!(e.errorDescription ?? "").isEmpty, "missing description for \(e)")
        }
    }

    @Test("network error inlines the message")
    func networkInlinesMessage() {
        let e = UpdateError.networkError("HTTP 500")
        #expect(e.errorDescription?.contains("HTTP 500") == true)
    }
}
