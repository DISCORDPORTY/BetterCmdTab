import Foundation

enum UpdateCheckInterval: String, CaseIterable, Identifiable, Codable {
    case manual
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        }
    }

    var description: String {
        switch self {
        case .manual: return "Only check when you click the button"
        case .automatic: return "Automatically check and install updates"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .manual:
            return nil
        case .automatic:
            #if DEBUG
            return 60 * 60
            #else
            return 24 * 60 * 60
            #endif
        }
    }
}

struct GitHubRelease: Codable, Sendable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let createdAt: Date
    let publishedAt: Date?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case assets
    }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Find the macOS app asset. Prefers .dmg over .zip; within each, prefers
    /// names that explicitly mention "macos".
    var macOSAsset: GitHubAsset? {
        let extensions = ["dmg", "zip"]
        for ext in extensions {
            let suffix = "." + ext
            if let preferred = assets.first(where: {
                $0.name.lowercased().hasSuffix(suffix) && $0.name.lowercased().contains("macos")
            }) {
                return preferred
            }
            if let any = assets.first(where: { $0.name.lowercased().hasSuffix(suffix) }) {
                return any
            }
        }
        return nil
    }
}

struct GitHubAsset: Codable, Sendable {
    let id: Int
    let name: String
    let label: String?
    let state: String
    let contentType: String
    let size: Int
    let downloadCount: Int
    let browserDownloadUrl: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case label
        case state
        case contentType = "content_type"
        case size
        case downloadCount = "download_count"
        case browserDownloadUrl = "browser_download_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Build number embedded in filename (e.g. BetterCmdTab-1.0.0-20260503141522.dmg → 20260503141522)
    var buildNumber: Int? {
        let baseName = name.components(separatedBy: ".").dropLast().joined(separator: ".")
        return baseName.components(separatedBy: "-").last.flatMap { Int($0) }
    }
}

enum UpdateCheckResult: Sendable {
    case upToDate
    case updateAvailable(release: GitHubRelease)
    case error(UpdateError)
}

enum UpdateError: Error, LocalizedError, Sendable {
    case networkError(String)
    case invalidResponse
    case noReleasesFound
    case parsingError(String)
    case downloadFailed(String)
    case installationFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .networkError(let message): return "Network error: \(message)"
        case .invalidResponse: return "Invalid response from GitHub"
        case .noReleasesFound: return "No releases found"
        case .parsingError(let message): return "Failed to parse release info: \(message)"
        case .downloadFailed(let message): return "Download failed: \(message)"
        case .installationFailed(let message): return "Installation failed: \(message)"
        case .userCancelled: return "Update cancelled"
        }
    }
}

enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case available(version: String, releaseNotes: String?)
    case downloading(progress: Double)
    case readyToInstall(localURL: URL)
    case installing(progress: Double, step: String)
    case error(String)
    case upToDate

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.checking, .checking),
             (.upToDate, .upToDate):
            return true
        case (.available(let v1, let n1), .available(let v2, let n2)):
            return v1 == v2 && n1 == n2
        case (.downloading(let p1), .downloading(let p2)):
            return p1 == p2
        case (.readyToInstall(let u1), .readyToInstall(let u2)):
            return u1 == u2
        case (.installing(let p1, let s1), .installing(let p2, let s2)):
            return p1 == p2 && s1 == s2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}
