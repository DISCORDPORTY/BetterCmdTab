import AppKit

/// A not-yet-running application discovered on disk. Carries only Sendable
/// fields so the index can be built off the main actor; the icon is fetched
/// lazily on access (main thread, at render time).
struct InstalledApp: Sendable, Hashable {
    let name: String
    let bundleID: String
    let url: URL

    var icon: NSImage? { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Catalog of installed apps, used by the switcher's search mode to offer
/// not-yet-running apps for launching. Built off-main and refreshed lazily so
/// it never blocks a reveal; matches exclude apps that are already running.
@MainActor
final class InstalledAppsIndex {
    static let shared = InstalledAppsIndex()

    private var apps: [InstalledApp] = []
    private var building = false
    private var lastBuilt: Date?
    /// Rebuild if the cache is older than this — picks up newly installed apps
    /// without rescanning on every search keystroke.
    private let staleness: TimeInterval = 120

    private init() {}

    /// Kick a background rebuild if the cache is empty or stale. Cheap to call
    /// repeatedly (e.g. each time search is entered).
    func ensureFresh() {
        if building { return }
        if let lastBuilt, Date().timeIntervalSince(lastBuilt) < staleness, !apps.isEmpty { return }
        building = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scanned = Self.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.apps = scanned
                self.building = false
                self.lastBuilt = Date()
            }
        }
    }

    /// Fuzzy-matched installed apps not already running, in scan order, capped
    /// at `limit`. Empty query returns nothing (launcher only augments an
    /// active search).
    func matches(query: String, excludingRunning runningBundleIDs: Set<String>, limit: Int) -> [InstalledApp] {
        guard !query.isEmpty else { return [] }
        var result: [InstalledApp] = []
        var seen = Set<String>()
        for app in apps {
            if runningBundleIDs.contains(app.bundleID) { continue }
            if seen.contains(app.bundleID) { continue }
            if FuzzyMatch.matches(query: query, appName: app.name, windowTitle: "") {
                result.append(app)
                seen.insert(app.bundleID)
                if result.count >= limit { break }
            }
        }
        return result
    }

    // MARK: - Scanning

    /// Enumerate `.app` bundles in the standard locations. One level deep per
    /// directory (plus the Utilities subfolders listed) — enough to cover
    /// virtually every user-facing app without an expensive deep crawl.
    nonisolated static func scan() -> [InstalledApp] {
        let searchDirectories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        let fm = FileManager.default
        var result: [InstalledApp] = []
        var seenBundleIDs = Set<String>()

        for dir in searchDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seenBundleIDs.contains(bundleID) else { continue }
                seenBundleIDs.insert(bundleID)
                // `displayName(atPath:)` respects localization, but returns a
                // trailing ".app" when the user enabled "show all filename
                // extensions" in Finder — strip it so the switcher never shows it.
                var name = fm.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name.removeLast(4) }
                result.append(InstalledApp(name: name, bundleID: bundleID, url: url))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
