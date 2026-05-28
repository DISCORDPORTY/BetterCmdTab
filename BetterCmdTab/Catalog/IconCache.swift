import AppKit

@MainActor
enum IconCache {
    /// Hard cap on cached entries per cache. Halved from 64 → 32 once
    /// `prewarm` was dropped: cache fills on demand, not all at launch, so
    /// the working set in steady state is closer to "apps the user actually
    /// invokes" than "every running process".
    private static let capacity = 32
    /// Edge length (px) of the flattened raster we cache. Sized just above the
    /// largest *typical* on-screen tile: the default "Medium" panel scale
    /// renders icons at ~77pt → 154px on a 2x Mac, and "Large" pushes the
    /// tile to ~190px. 256 keeps the largest case crisp while shaving 36%
    /// off the per-entry RAM (320² → 256²).
    private static let renderEdge = 256
    /// Byte cost of one flattened entry (used as the NSCache cost). A 256²
    /// RGBA bitmap is ~262 KB, so the cap doubles as a real memory ceiling
    /// (~8 MB per cache, ~16 MB across both — down from ~52 MB).
    private static let bytesPerImage = renderEdge * renderEdge * 4

    /// `NSCache` rather than a hand-rolled LRU dict so the system can evict
    /// flattened icons automatically under memory pressure (and the count/cost
    /// limits bound steady-state footprint). Keyed by pid for running apps.
    private static let cache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.countLimit = capacity
        c.totalCostLimit = capacity * bytesPerImage
        return c
    }()
    /// Sibling cache for launchable + recently-closed rows that have no pid.
    /// Without this every search keystroke would re-fetch the disk icon for
    /// each of the up-to-8 launcher rows + recently-closed rows: a steady
    /// stream of `NSWorkspace.icon(forFile:)` calls on the main actor.
    private static let bundleCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = capacity
        c.totalCostLimit = capacity * bytesPerImage
        return c
    }()

    static func icon(for row: SwitcherRow) -> NSImage? {
        if let pid = row.pid {
            let key = NSNumber(value: pid)
            if let cached = cache.object(forKey: key) { return cached }
            guard let source = row.app?.icon else { return row.icon }
            let flat = flattened(source) ?? source
            cache.setObject(flat, forKey: key, cost: bytesPerImage)
            return flat
        }
        // No pid → launchable or recently-closed. Key by bundle ID so a
        // search session that lists the same apps on every keystroke reads
        // from memory instead of round-tripping `NSWorkspace`.
        guard let bundleID = row.bundleIdentifier, !bundleID.isEmpty else { return row.icon }
        let key = bundleID as NSString
        if let cached = bundleCache.object(forKey: key) { return cached }
        guard let source = row.icon else { return nil }
        let flat = flattened(source) ?? source
        bundleCache.setObject(flat, forKey: key, cost: bytesPerImage)
        return flat
    }

    static func evict(_ pid: pid_t) {
        cache.removeObject(forKey: NSNumber(value: pid))
    }

    static func clear() {
        cache.removeAllObjects()
        bundleCache.removeAllObjects()
    }

    /// Kept as a no-op for callers that used to eagerly populate the cache.
    /// Eager prewarm was both an autolayout-thread hazard (Tahoe restyles
    /// bundle icons via lazily-initialized AppKit views, which writes to the
    /// layout engine when `NSImage.draw` runs off the main thread) and the
    /// single biggest contributor to the post-launch RSS spike (~12 MB for a
    /// 30-app system). On-demand flatten covers every icon a user actually
    /// sees with negligible first-paint cost (≤1 ms per icon on M-series).
    static func prewarm(pids: [pid_t]) {
        _ = pids
    }

    /// Rasterize an app icon into a fixed-size, immutable bitmap.
    ///
    /// On macOS 26 (Tahoe) the system restyles legacy app icons on the fly
    /// (rounded-rect mask + Liquid Glass material). `NSRunningApplication.icon`
    /// hands back a *live* `NSImage` whose representations IconServices fills in
    /// lazily: the view paints the raw `.icns` rep first, then AppKit swaps in
    /// the styled rendition under the same object — a visible old→new flicker.
    /// Drawing once into our own bitmap resolves the styled rendition right
    /// here and yields an image AppKit won't mutate afterwards, so the swap
    /// (and its flicker) can't happen. The styling cost is also paid once
    /// rather than on every redraw.
    ///
    /// `@MainActor` — bundle icons under Tahoe trigger AppKit view init
    /// during `image.draw`, which touches the AutoLayout engine. Running
    /// this off the main thread raised
    /// `NSInternalInconsistencyException: Modifications to the layout
    /// engine must not be performed from a background thread...`
    private static func flattened(_ image: NSImage) -> NSImage? {
        let size = NSSize(width: renderEdge, height: renderEdge)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: renderEdge,
            pixelsHigh: renderEdge,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        ctx.flushGraphics()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
