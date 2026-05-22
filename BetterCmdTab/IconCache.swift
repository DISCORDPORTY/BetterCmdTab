import AppKit

enum IconCache {
    private static var cache: [pid_t: NSImage] = [:]

    static func icon(for row: SwitcherRow) -> NSImage? {
        if let cached = cache[row.pid] { return cached }
        guard let image = row.app.icon else { return nil }
        cache[row.pid] = image
        return image
    }

    static func evict(_ pid: pid_t) {
        cache.removeValue(forKey: pid)
    }

    static func clear() {
        cache.removeAll()
    }
}
