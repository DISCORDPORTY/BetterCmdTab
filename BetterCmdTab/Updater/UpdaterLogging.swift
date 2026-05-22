import Foundation
import os.log

enum BCTLog {
    private static let subsystem: String = {
        Bundle.main.bundleIdentifier ?? "pro.bettercmdtab.BetterCmdTab"
    }()

    static let updater = Category(subsystem: subsystem, category: "updater")

    struct Category: Sendable {
        private let logger: Logger
        private let name: String

        init(subsystem: String, category: String) {
            self.logger = Logger(subsystem: subsystem, category: category)
            self.name = category
        }

        @inlinable nonisolated func debug(_ message: String) {
            #if DEBUG
            logger.debug("[\(self.name, privacy: .public)] \(message, privacy: .public)")
            #endif
        }
        @inlinable nonisolated func info(_ message: String) {
            logger.info("[\(self.name, privacy: .public)] \(message, privacy: .public)")
        }
        @inlinable nonisolated func notice(_ message: String) {
            logger.notice("[\(self.name, privacy: .public)] \(message, privacy: .public)")
        }
        @inlinable nonisolated func warn(_ message: String) {
            logger.warning("[\(self.name, privacy: .public)] \(message, privacy: .public)")
        }
        @inlinable nonisolated func error(_ message: String) {
            logger.error("[\(self.name, privacy: .public)] \(message, privacy: .public)")
        }
    }
}

enum AppInfo {
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    static let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    static let displayName = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
        ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
        ?? "BetterCmdTab"
}
