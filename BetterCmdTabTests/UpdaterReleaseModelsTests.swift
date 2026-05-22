import Foundation
import Testing
@testable import BetterCmdTab

@Suite("GitHubAsset.buildNumber")
struct GitHubAssetBuildNumberTests {

    private func asset(name: String) -> GitHubAsset {
        GitHubAsset(
            id: 1,
            name: name,
            label: nil,
            state: "uploaded",
            contentType: "application/octet-stream",
            size: 1,
            downloadCount: 0,
            browserDownloadUrl: "https://example.com/\(name)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("trailing timestamp parses to Int")
    func timestampParses() {
        let a = asset(name: "BetterCmdTab-1.0.0-20260503141522.dmg")
        #expect(a.buildNumber == 20260503141522)
    }

    @Test("timestamp survives extra hyphen segments")
    func multiSegment() {
        let a = asset(name: "BetterCmdTab-1.0.0-beta.2-20260503141522.zip")
        #expect(a.buildNumber == 20260503141522)
    }

    @Test("non-numeric tail returns nil")
    func nonNumericTail() {
        let a = asset(name: "BetterCmdTab-latest.dmg")
        #expect(a.buildNumber == nil)
    }

    @Test("name without hyphen returns nil")
    func noHyphen() {
        let a = asset(name: "Bundle.dmg")
        #expect(a.buildNumber == nil)
    }

    @Test("formattedSize emits a non-empty string")
    func formattedSizeNonEmpty() {
        let a = GitHubAsset(
            id: 1, name: "a.dmg", label: nil, state: "uploaded",
            contentType: "application/octet-stream", size: 1_500_000,
            downloadCount: 0, browserDownloadUrl: "x",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(!a.formattedSize.isEmpty)
    }
}

@Suite("GitHubRelease.macOSAsset")
struct GitHubReleaseAssetSelectionTests {

    private func asset(_ name: String) -> GitHubAsset {
        GitHubAsset(
            id: Int.random(in: 1...Int.max),
            name: name,
            label: nil,
            state: "uploaded",
            contentType: "application/octet-stream",
            size: 1,
            downloadCount: 0,
            browserDownloadUrl: "https://example.com/\(name)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func release(tag: String, assets: [GitHubAsset]) -> GitHubRelease {
        GitHubRelease(
            id: 1,
            tagName: tag,
            name: nil,
            body: nil,
            draft: false,
            prerelease: false,
            createdAt: Date(timeIntervalSince1970: 0),
            publishedAt: nil,
            htmlUrl: "https://example.com/r",
            assets: assets
        )
    }

    @Test("prefers DMG over ZIP")
    func dmgOverZip() {
        let r = release(tag: "v1.0.0", assets: [
            asset("BetterCmdTab-1.0.0.zip"),
            asset("BetterCmdTab-1.0.0.dmg")
        ])
        #expect(r.macOSAsset?.name == "BetterCmdTab-1.0.0.dmg")
    }

    @Test("within DMGs, prefers macos-named asset")
    func macosNamePreferred() {
        let r = release(tag: "v1.0.0", assets: [
            asset("BetterCmdTab-1.0.0.dmg"),
            asset("BetterCmdTab-1.0.0-macos.dmg")
        ])
        #expect(r.macOSAsset?.name == "BetterCmdTab-1.0.0-macos.dmg")
    }

    @Test("falls back to ZIP when no DMG present")
    func zipFallback() {
        let r = release(tag: "v1.0.0", assets: [
            asset("Source.tar.gz"),
            asset("BetterCmdTab-1.0.0.zip")
        ])
        #expect(r.macOSAsset?.name == "BetterCmdTab-1.0.0.zip")
    }

    @Test("returns nil when no DMG or ZIP")
    func noMatch() {
        let r = release(tag: "v1.0.0", assets: [
            asset("Source.tar.gz"),
            asset("notes.txt")
        ])
        #expect(r.macOSAsset == nil)
    }

    @Test("version strips leading v from tagName")
    func versionStripsV() {
        #expect(release(tag: "v1.2.3", assets: []).version == "1.2.3")
    }

    @Test("version keeps non-v tag verbatim")
    func versionKeepsNonV() {
        #expect(release(tag: "1.2.3", assets: []).version == "1.2.3")
    }
}

@Suite("UpdateCheckInterval")
struct UpdateCheckIntervalTests {
    @Test("manual has no interval")
    func manualNoInterval() {
        #expect(UpdateCheckInterval.manual.interval == nil)
    }

    @Test("automatic resolves to a positive interval")
    func automaticHasInterval() {
        let interval = UpdateCheckInterval.automatic.interval
        #expect(interval != nil)
        #expect((interval ?? 0) > 0)
    }

    @Test("raw values stable")
    func rawValuesStable() {
        // UserDefaults persists these strings; renaming would silently lose user prefs.
        #expect(UpdateCheckInterval.manual.rawValue == "manual")
        #expect(UpdateCheckInterval.automatic.rawValue == "automatic")
    }
}
