import AppKit
import ScreenCaptureKit

/// Samples the tab-strip/toolbar color of browser windows so their pills can wear the window's theme.
/// Needs Screen Recording permission; without it no colors are returned.
enum BrowserTheme {
    static let browserIDs: Set<String> = [
        "com.google.Chrome", "ai.perplexity.comet", "org.mozilla.firefox", "com.apple.Safari",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
    ]

    static func isBrowser(_ entry: AppEntry) -> Bool {
        entry.bundleID.map(browserIDs.contains) ?? false
    }

    /// Asks for Screen Recording once; afterwards the user decides in System Settings.
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let key = "askedScreenRecording"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            CGRequestScreenCaptureAccess()
        }
        return false
    }

    /// Theme color per window ID.
    static func colors(for windowIDs: [CGWindowID]) async -> [CGWindowID: NSColor] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }
        let wanted = Set(windowIDs)
        let windows = content.windows.filter { wanted.contains($0.windowID) }
        return await withTaskGroup(of: (CGWindowID, NSColor?).self) { group in
            for w in windows {
                group.addTask { (w.windowID, await sample(w)) }
            }
            var result: [CGWindowID: NSColor] = [:]
            for await (id, color) in group { if let color { result[id] = color } }
            return result
        }
    }

    /// Dominant color of the top strip of the window (tab strip / title bar).
    private static func sample(_ window: SCWindow) async -> NSColor? {
        let stripH: CGFloat = 12
        let width = window.frame.width
        guard width > 40 else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: 0, y: 2, width: width, height: stripH)
        cfg.width = Int(width)
        cfg.height = Int(stripH)
        cfg.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: cfg) else { return nil }
        return dominantColor(image)
    }

    private static func dominantColor(_ image: CGImage) -> NSColor? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Bucket colors to 4 bits per channel, pick the most common bucket, average its pixels.
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let e = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (e.count + 1, e.r + r, e.g + g, e.b + b)
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let n = CGFloat(best.count) * 255
        return NSColor(srgbRed: CGFloat(best.r) / n, green: CGFloat(best.g) / n, blue: CGFloat(best.b) / n, alpha: 1)
    }
}
