import AppKit
import CoreImage

/// Full-screen transparent panel that hosts the rays.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// A set of views that fly out from `origin` to their targets.
private struct RayGroup {
    var origin: NSPoint
    var items: [(view: NSView, target: NSPoint)] = []
    var progress: CGFloat = 0

    func layout() {
        let e = 1 - pow(1 - progress, 3) // ease-out cubic
        for (v, t) in items {
            let c = NSPoint(x: origin.x + (t.x - origin.x) * e, y: origin.y + (t.y - origin.y) * e)
            v.setFrameOrigin(NSPoint(x: c.x - v.frame.width / 2, y: c.y - v.frame.height / 2))
            v.alphaValue = min(1, progress * 1.6)
        }
    }
}

final class RadialView: NSView {
    var onDismiss: (() -> Void)?
    var onPick: ((AppEntry, WindowEntry?) -> Void)?

    private let hub: NSPoint
    private let safe: NSRect
    private var appRays: RayGroup
    private var winRays: RayGroup?
    private var bubbles: [AppBubble] = []
    private var pills: [WindowPill] = []
    private var pillsOnRight = true
    private weak var selected: AppBubble?
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    private static let duration: CGFloat = 0.28

    /// Final centers of the app bubbles by bundle ID, in view coordinates.
    var bubbleCenters: [String: NSPoint] {
        Dictionary(appRays.items.compactMap { item in
            (item.view as? AppBubble)?.app.bundleID.map { ($0, item.target) }
        }, uniquingKeysWith: { a, _ in a })
    }

    /// `aims`: where each numbered app's follow-up lines go, by bundle ID, in view coordinates.
    init(frame: NSRect, hub: NSPoint, safe: NSRect, apps: [AppEntry], aims: [String: NSPoint] = [:]) {
        self.hub = hub
        self.safe = safe
        self.appRays = RayGroup(origin: hub)
        super.init(frame: frame)

        var spots = RadialView.ringTargets(count: apps.count, hub: hub, safe: safe)
        var placed = [NSPoint?](repeating: nil, count: apps.count)
        // Numbered apps take the free spot closest to where their lines go (closest pair first),
        // so the lines run outward without crossing other apps. The rest keep their usual order.
        var pending = apps.indices.filter { apps[$0].bundleID.flatMap { aims[$0] } != nil }
        while !pending.isEmpty && !spots.isEmpty {
            var best = (d: CGFloat.infinity, app: 0, spot: 0)
            for a in pending {
                let aim = aims[apps[a].bundleID!]!
                for (s, p) in spots.enumerated() where hypot(p.x - aim.x, p.y - aim.y) < best.d {
                    best = (hypot(p.x - aim.x, p.y - aim.y), a, s)
                }
            }
            placed[best.app] = spots.remove(at: best.spot)
            pending.removeAll { $0 == best.app }
        }
        for i in apps.indices where placed[i] == nil && !spots.isEmpty {
            placed[i] = spots.removeFirst()
        }
        for (app, target) in zip(apps, placed) {
            if let target { addBubble(app, at: target) }
        }
        appRays.layout()
        startAnimating()
    }

    @discardableResult
    private func addBubble(_ app: AppEntry, at target: NSPoint) -> AppBubble {
        let b = AppBubble(app: app)
        b.onClick = { [weak self, weak b] in if let b { self?.select(b) } }
        b.onRightClick = { [weak self, weak b] in if let b { self?.quit(b) } }
        addSubview(b)
        bubbles.append(b)
        appRays.items.append((b, target))
        return b
    }

    /// Right-click on an app: quit it (and with it all its windows).
    private func quit(_ bubble: AppBubble) {
        guard let running = bubble.app.app else { return }
        running.terminate()
        if selected === bubble { clearSelection() }
        let target = appRays.items.first { $0.view === bubble }!.target
        bubble.removeFromSuperview()
        bubbles.removeAll { $0 === bubble }
        appRays.items.removeAll { $0.view === bubble }
        // Screen Sharing stays in the ring, grayed out.
        if bubble.app.isScreenSharing, let placeholder = AppEntry(notRunningBundleID: screenSharingBundleID) {
            let b = addBubble(placeholder, at: target)
            b.setFrameOrigin(NSPoint(x: target.x - b.frame.width / 2, y: target.y - b.frame.height / 2))
        }
        needsDisplay = true
    }

    /// Right-click on a pill: close that window, or drop that follow-up (numbers close up).
    private func close(_ pill: WindowPill) {
        if case .followUp(let f, _) = pill.kind {
            FollowUpStore.shared.remove(f)
            bubbles.forEach { $0.needsDisplay = true }
            if let sel = selected { select(sel) }
            return
        }
        guard case .window(let w) = pill.kind else { return }
        WindowService.close(w)
        pill.removeFromSuperview()
        pills.removeAll { $0 === pill }
        winRays?.items.removeAll { $0.view === pill }
        if pills.isEmpty { clearSelection() }
        needsDisplay = true
    }

    private func clearSelection() {
        selected = nil
        pills.forEach { $0.removeFromSuperview() }
        pills = []
        winRays = nil
        for b in bubbles {
            b.isSelected = false
            b.dimmed = false
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } // Esc
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?() // click on empty space closes the rays
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { timer?.invalidate() }
    }

    // MARK: Layout

    /// Staggered rings around the hub, filled from the inside out, clockwise. Spots off screen are
    /// skipped, so near an edge or corner the rings become arcs that open away from it.
    static func ringTargets(count n: Int, hub: NSPoint, safe: NSRect) -> [NSPoint] {
        guard n > 0 else { return [] }
        let spacing: CGFloat = 92, ringGap: CGFloat = 92, edgeMargin: CGFloat = 200
        let area = safe.insetBy(dx: 44, dy: 46) // bubble centers keep the whole bubble on screen

        // Start each ring at the side facing the nearest edges, so the visible arc runs unbroken.
        var toward = CGVector(dx: 0, dy: 0)
        if hub.x - safe.minX < edgeMargin { toward.dx -= 1 }
        if safe.maxX - hub.x < edgeMargin { toward.dx += 1 }
        if hub.y - safe.minY < edgeMargin { toward.dy -= 1 }
        if safe.maxY - hub.y < edgeMargin { toward.dy += 1 }
        let startAngle = toward.dx == 0 && toward.dy == 0 ? CGFloat.pi / 2 : atan2(toward.dy, toward.dx)

        var result: [NSPoint] = []
        var r: CGFloat = 105, ring = 0
        while result.count < n && r < 4000 {
            let k = max(6, Int(2 * .pi * r / spacing))
            let offset: CGFloat = ring % 2 == 1 ? 0.5 : 0
            let spots = (0..<k).map { i -> NSPoint in
                let a = startAngle - 2 * .pi * (CGFloat(i) + offset) / CGFloat(k)
                return NSPoint(x: hub.x + cos(a) * r, y: hub.y + sin(a) * r)
            }.filter(area.contains)
            let need = n - result.count
            if spots.count <= need {
                result += spots
            } else { // last ring: spread the rest evenly along it
                result += (0..<need).map { spots[Int((CGFloat($0) + 0.5) * CGFloat(spots.count) / CGFloat(need))] }
            }
            r += ringGap
            ring += 1
        }
        return result
    }

    private func select(_ bubble: AppBubble) {
        selected = bubble
        for b in bubbles {
            b.isSelected = b === bubble
            b.dimmed = b !== bubble
        }
        pills.forEach { $0.removeFromSuperview() }
        pills = []

        let app = bubble.app
        let store = FollowUpStore.shared
        var kinds: [WindowPill.Kind] = store.items(for: app.bundleID).map { .followUp($0, store.number(of: $0) ?? 0) }
        var windows: [WindowEntry] = []
        if app.isRunning {
            if WindowService.isTrusted {
                windows = WindowService.windows(of: app)
                kinds += windows.map { .window($0) }
            } else {
                kinds.append(.grantAccess)
            }
        }
        NSLog("DDD select %@ running=%d trusted=%d windows=%d", app.name, app.isRunning ? 1 : 0,
              WindowService.isTrusted ? 1 : 0, windows.count)
        if app.isScreenSharing {
            kinds += MachineService.shared.machines.map { .machine($0) }
        }
        if kinds.isEmpty { kinds = [.activate] }

        // A single window needs no choice: go straight to it.
        if kinds.count == 1, case .window = kinds[0] {
            pick(app, kinds[0])
            return
        }

        // Up to two columns of pills; beyond that the list is cut.
        let rowH: CGFloat = 40
        let maxRows = max(1, Int((safe.height - 20) / rowH))
        if kinds.count > maxRows * 2 { kinds = Array(kinds.prefix(maxRows * 2)) }
        let rows = min(kinds.count, maxRows)

        for kind in kinds {
            let p = WindowPill(app: app, kind: kind)
            p.onClick = { [weak self] in self?.pick(app, kind) }
            p.onRightClick = { [weak self, weak p] in if let p { self?.close(p) } }
            addSubview(p)
            pills.append(p)
        }

        // Pills fan out from the app on the side away from the hub.
        let appC = appRays.items.first { $0.view === bubble }!.target
        let dx = appC.x - hub.x, dy = appC.y - hub.y
        let len = max(1, hypot(dx, dy))
        let maxW = pills.map(\.frame.width).max() ?? 0
        let cols = (pills.count + rows - 1) / rows
        let blockW = CGFloat(cols) * maxW + CGFloat(cols - 1) * 24
        var right = dx >= 0
        if right && appC.x + 90 + blockW > safe.maxX - 10 { right = false }
        if !right && appC.x - 90 - blockW < safe.minX + 10 { right = true }
        pillsOnRight = right

        let totalH = CGFloat(rows) * rowH
        var topY = appC.y + dy / len * 50 + totalH / 2 - rowH / 2
        topY = min(topY, safe.maxY - rowH / 2 - 6)
        topY = max(topY, safe.minY + totalH - rowH / 2 + 6)

        var group = RayGroup(origin: appC)
        for (i, p) in pills.enumerated() {
            let col = CGFloat(i / rows), row = CGFloat(i % rows)
            let edge = 90 + col * (maxW + 24)
            let x = right ? appC.x + edge + p.frame.width / 2 : appC.x - edge - p.frame.width / 2
            group.items.append((p, NSPoint(x: x, y: topY - row * rowH)))
        }
        winRays = group
        group.layout()
        startAnimating()

        if BrowserTheme.isBrowser(app), !windows.isEmpty, BrowserTheme.ensurePermission() {
            applyThemeColors(windows: windows)
        }
    }

    private func applyThemeColors(windows: [WindowEntry]) {
        let ids = windows.compactMap(\.windowID)
        let currentPills = pills
        Task { @MainActor in
            let colors = await BrowserTheme.colors(for: ids)
            for p in currentPills {
                if case .window(let w) = p.kind, let id = w.windowID { p.themeColor = colors[id] }
            }
        }
    }

    private func pick(_ app: AppEntry, _ kind: WindowPill.Kind) {
        switch kind {
        case .window(let w): onPick?(app, w)
        case .activate: onPick?(app, nil)
        case .followUp(let f, _):
            onDismiss?()
            FollowUpOpener.open(f)
        case .machine(let m):
            onDismiss?()
            if let url = m.vncURL { NSWorkspace.shared.open(url) }
        case .grantAccess:
            WindowService.promptForTrust()
            WindowService.openAccessibilitySettings()
            onDismiss?()
        }
    }

    // MARK: Animation

    private func startAnimating() {
        lastTick = CACurrentMediaTime()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 120, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let step = CGFloat(now - lastTick) / RadialView.duration
        lastTick = now
        appRays.progress = min(1, appRays.progress + step)
        appRays.layout()
        if winRays != nil {
            winRays!.progress = min(1, winRays!.progress + step)
            winRays!.layout()
        }
        needsDisplay = true
        if appRays.progress >= 1 && (winRays?.progress ?? 1) >= 1 {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        for b in bubbles {
            let path = NSBezierPath()
            path.move(to: hub)
            path.line(to: NSPoint(x: b.frame.midX, y: b.frame.midY))
            let isSel = b === selected
            (isSel ? NSColor.controlAccentColor : NSColor.white)
                .withAlphaComponent((isSel ? 0.95 : (selected == nil ? 0.45 : 0.18)) * b.alphaValue).setStroke()
            path.lineWidth = isSel ? 2.5 : 1.5
            path.stroke()
        }

        // Mind-map style branches from the selected app to each pill.
        if let sel = selected {
            let from = NSPoint(x: sel.frame.midX, y: sel.frame.midY)
            for p in pills {
                let to = NSPoint(x: pillsOnRight ? p.frame.minX : p.frame.maxX, y: p.frame.midY)
                let midX = from.x + (to.x - from.x) * 0.5
                let path = NSBezierPath()
                path.move(to: from)
                path.curve(to: to, controlPoint1: NSPoint(x: midX, y: from.y), controlPoint2: NSPoint(x: midX, y: to.y))
                (p.themeColor ?? NSColor.controlAccentColor).withAlphaComponent(0.75 * p.alphaValue).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }
}

// MARK: - Items

private class HoverView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var hovered = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onRightClick?() }
    }

    static func label(size: CGFloat, weight: NSFont.Weight, color: NSColor,
                      align: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        return [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: para]
    }
}

private final class AppBubble: HoverView {
    let app: AppEntry
    private let icon: NSImage
    var isSelected = false { didSet { needsDisplay = true } }
    var dimmed = false { didSet { needsDisplay = true } }

    init(app: AppEntry) {
        self.app = app
        self.icon = app.isRunning ? app.icon : app.icon.grayscale
        super.init(frame: NSRect(x: 0, y: 0, width: 82, height: 86))
        toolTip = app.isRunning ? app.name : "\(app.name) (not running)"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        var a: CGFloat = dimmed && !hovered ? 0.45 : 1
        if !app.isRunning && !hovered && !isSelected { a *= 0.6 }
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 16, yRadius: 16)
        (hovered || isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.9)
                               : NSColor(white: 0.08, alpha: 0.72 * a)).setFill()
        bg.fill()
        icon.draw(in: NSRect(x: (bounds.width - 50) / 2, y: 28, width: 50, height: 50),
                  from: .zero, operation: .sourceOver, fraction: a)
        (app.name as NSString).draw(
            with: NSRect(x: 8, y: 8, width: bounds.width - 16, height: 16),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: HoverView.label(size: 11, weight: .medium, color: .white.withAlphaComponent(a), align: .center))

        // Follow-up numbers for this app ("2·5"), or just how many when there are lots.
        let store = FollowUpStore.shared
        let numbers = store.items(for: app.bundleID).compactMap(store.number(of:))
        if !numbers.isEmpty {
            drawBadge(numbers.count <= 3 ? numbers.map(String.init).joined(separator: "·") : "\(numbers.count)", in: bounds)
        }
    }
}

private final class WindowPill: HoverView {
    enum Kind {
        case window(WindowEntry)
        case activate
        case machine(Machine)
        case followUp(FollowUp, Int)
        case grantAccess
    }

    let app: AppEntry
    let kind: Kind
    /// Browser theme color sampled from the window; nil = default dark pill.
    var themeColor: NSColor? { didSet { needsDisplay = true } }
    private let text: String
    private let detail: String?
    private let subtle: Bool
    private let symbol: NSImage?
    private var number: Int?

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    init(app: AppEntry, kind: Kind) {
        self.app = app
        self.kind = kind
        var detail: String?
        var symbol: NSImage?
        switch kind {
        case .window(let w):
            text = w.title.isEmpty ? app.name : w.title
            detail = w.minimized ? "minimized" : nil
            subtle = w.minimized
        case .activate:
            text = app.isRunning ? "No open windows — bring \(app.name) to front" : "Open \(app.name)"
            subtle = true
        case .machine(let m):
            text = m.name
            detail = m.online ? "Tailscale" : "offline"
            subtle = !m.online
            symbol = NSImage(systemSymbolName: m.os == "macOS" ? "desktopcomputer" : "server.rack",
                             accessibilityDescription: nil)
        case .followUp(let f, let n):
            text = f.label
            subtle = false
            number = n
        case .grantAccess:
            text = "Allow DDD in Accessibility settings to list windows…"
            subtle = false
        }
        self.detail = detail
        self.symbol = symbol
        let textW = (text as NSString).size(withAttributes: [.font: WindowPill.font]).width
        let detailW = detail.map { ($0 as NSString).size(withAttributes: [.font: WindowPill.detailFont]).width + 10 } ?? 0
        let width = min(380, max(150, textW + detailW + 52))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        toolTip = text
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 15, yRadius: 15)
        let fill: NSColor
        if let theme = themeColor {
            fill = hovered ? (theme.blended(withFraction: 0.15, of: .white) ?? theme) : theme
        } else {
            fill = hovered ? .controlAccentColor : NSColor(white: 0.1, alpha: 0.9)
        }
        fill.setFill()
        bg.fill()
        (hovered && themeColor != nil ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.18)).setStroke()
        bg.lineWidth = hovered && themeColor != nil ? 2.5 : 1
        bg.stroke()

        let fg: NSColor = fill.isLight ? .black : .white
        let iconRect = NSRect(x: 9, y: 7, width: 18, height: 18)
        if let number {
            let circle = NSRect(x: 6, y: 5, width: 22, height: 22)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: circle).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold),
                                                        .foregroundColor: NSColor.white]
            let t = "\(number)" as NSString
            let sz = t.size(withAttributes: attrs)
            t.draw(at: NSPoint(x: circle.midX - sz.width / 2, y: circle.midY - sz.height / 2), withAttributes: attrs)
        } else if let symbol {
            let tinted = symbol.tinted(fg.withAlphaComponent(subtle && !hovered ? 0.5 : 0.9))
            tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            app.icon.draw(in: iconRect)
        }

        var textRight = bounds.width - 12
        if let detail {
            let attrs = HoverView.label(size: 11, weight: .regular, color: fg.withAlphaComponent(0.55), align: .right)
            let w = (detail as NSString).size(withAttributes: attrs).width
            (detail as NSString).draw(with: NSRect(x: bounds.width - 12 - w, y: 9, width: w, height: 15),
                                      options: [.usesLineFragmentOrigin], attributes: attrs)
            textRight -= w + 10
        }
        let color = fg.withAlphaComponent(subtle && !hovered ? 0.6 : 1)
        (text as NSString).draw(
            with: NSRect(x: 33, y: 8, width: textRight - 33, height: 17),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: HoverView.label(size: 13, weight: .medium, color: color, align: .left))
    }
}

private extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.62
    }
}

private extension NSImage {
    var grayscale: NSImage {
        guard let tiff = tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return self }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let out = filter.outputImage else { return self }
        let img = NSImage(size: size)
        img.addRepresentation(NSCIImageRep(ciImage: out))
        return img
    }

    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
