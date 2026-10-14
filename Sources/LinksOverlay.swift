import AppKit
import ApplicationServices

/// Thin always-on-top lines from the D to each follow-up's place: its window, or its Dock item when
/// the window is minimized (or the app is hidden / has no window). Click-through; one panel per screen.
/// Each line ends in a small ring that opens its follow-up when clicked, shows its app's name on hover,
/// and removes the follow-up on right-click. Lines turn green while their app asks for input
/// (a badge on its Dock icon, or a sheet/dialog open).
final class LinksOverlay {
    /// Center of the D in global Cocoa coordinates.
    var hub: () -> NSPoint = { .zero }
    /// While the app ring is open: center of each app's bubble by bundle ID (global Cocoa coordinates);
    /// lines then start at the edge of their app's bubble instead of the D.
    var starts: [String: NSPoint]? { didSet { redraw() } }
    /// Called just before a ring opens its follow-up.
    var onOpen: (() -> Void)?

    private var panels: [LinksPanel] = []
    private var rings: [RingPanel] = []
    /// Target rects in global CG coordinates (top-left origin), one per follow-up.
    private var targets: [(followUp: FollowUp, rect: CGRect, needsInput: Bool)] = []
    private var timer: Timer?
    private var busy = false
    private let queue = DispatchQueue(label: "io.prim.ddd.links")

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        rebuildPanels()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        rings.forEach { $0.orderOut(nil) }
        rings = []
    }

    func rebuildPanels() {
        guard timer != nil else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map(LinksPanel.init)
        panels.forEach { $0.orderFrontRegardless() }
        redraw()
    }

    /// Re-reads window/Dock positions off the main thread (AX calls can be slow).
    func refresh() {
        guard timer != nil, !busy else { return }
        busy = true
        let items = FollowUpStore.shared.items
        queue.async { [weak self] in
            let dock = LinksOverlay.dockItems()
            let rects = items.compactMap { f in LinksOverlay.place(of: f, dock: dock).map { (f, $0.rect, $0.needsInput) } }
            DispatchQueue.main.async {
                self?.busy = false
                self?.targets = rects
                self?.redraw()
            }
        }
    }

    /// Lines from the hub (or the app's bubble) to a ring at the center of each target.
    func redraw() {
        guard timer != nil else { return }
        let primaryH = NSScreen.screens.first?.frame.maxY ?? 0
        var ends: [NSPoint] = []
        var lines: [(from: NSPoint, to: NSPoint, needsInput: Bool)] = []
        for t in targets {
            var to = NSPoint(x: t.rect.midX, y: primaryH - t.rect.midY)
            // Follow-ups in the same window: step rings aside so each one stays clickable.
            while ends.contains(where: { hypot($0.x - to.x, $0.y - to.y) < RingPanel.size }) { to.x += RingPanel.size + 4 }
            ends.append(to)
            var from = hub()
            if let c = starts?[t.followUp.bundleID] {
                let len = max(1, hypot(to.x - c.x, to.y - c.y))
                let r = min(44, len) // start at the bubble's edge, not under its icon
                from = NSPoint(x: c.x + (to.x - c.x) / len * r, y: c.y + (to.y - c.y) / len * r)
            }
            // End the line at the ring's edge so the ring's hole stays clear.
            let len = max(1, hypot(to.x - from.x, to.y - from.y))
            let r = min(RingPanel.size / 2 - 3, len)
            lines.append((from, NSPoint(x: to.x - (to.x - from.x) / len * r, y: to.y - (to.y - from.y) / len * r), t.needsInput))
        }
        panels.forEach { $0.linesView.lines = lines }

        while rings.count < targets.count {
            let ring = RingPanel()
            ring.onClick = { [weak self, weak ring] in
                guard let f = ring?.followUp else { return }
                self?.onOpen?()
                FollowUpOpener.open(f)
            }
            ring.onRightClick = { [weak self, weak ring] in
                guard let f = ring?.followUp else { return }
                // Drop the line at once; the store's change notification refreshes the rest.
                self?.targets.removeAll { $0.followUp.id == f.id }
                FollowUpStore.shared.remove(f)
                self?.redraw()
            }
            ring.orderFrontRegardless()
            rings.append(ring)
        }
        while rings.count > targets.count { rings.removeLast().orderOut(nil) }
        for (ring, (t, c)) in zip(rings, zip(targets, ends)) {
            ring.followUp = t.followUp
            ring.needsInput = t.needsInput
            ring.setFrameOrigin(NSPoint(x: c.x - RingPanel.size / 2, y: c.y - RingPanel.size / 2))
        }
    }

    /// Where each app's lines go: the average center of its follow-ups' targets, by bundle ID (global Cocoa coordinates).
    var aims: [String: NSPoint] {
        let primaryH = NSScreen.screens.first?.frame.maxY ?? 0
        return Dictionary(grouping: targets, by: \.followUp.bundleID).mapValues { ts in
            NSPoint(x: ts.map(\.rect.midX).reduce(0, +) / CGFloat(ts.count),
                    y: primaryH - ts.map(\.rect.midY).reduce(0, +) / CGFloat(ts.count))
        }
    }

    /// Put the lines and rings above other DDD panels (e.g. the app ring).
    func bringToFront() {
        panels.forEach { $0.orderFrontRegardless() }
        rings.forEach { $0.orderFrontRegardless() }
    }

    // MARK: Places

    private struct DockItem {
        let title: String
        let subrole: String
        let url: URL?
        let frame: CGRect
        /// Dock badge text (e.g. unread count), empty when none.
        let badge: String
    }

    /// The follow-up's window (same pick as FollowUpOpener), else its minimized thumbnail or app icon in the Dock.
    /// `needsInput`: the app shows a Dock badge, or has a sheet or dialog open.
    private static func place(of f: FollowUp, dock: [DockItem]) -> (rect: CGRect, needsInput: Bool)? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: f.bundleID).first
        let windows = running.map { WindowService.windows(of: AppEntry(running: $0)) } ?? []
        let appPath = (running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: f.bundleID))?.path
        let appItem = dock.first { $0.subrole == "AXApplicationDockItem" && (($0.url?.path).map { $0 == appPath } ?? false) }
            ?? dock.first { $0.subrole == "AXApplicationDockItem" && $0.title == f.appName }
        let needsInput = !(appItem?.badge.isEmpty ?? true) || windows.contains { w in
            let subrole = WindowService.attribute(w.element, kAXSubroleAttribute) as? String
            return subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole
                || (WindowService.attribute(w.element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                    .contains { WindowService.attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }
        }
        if let running, !running.isHidden, let w = windows.first(where: { $0.title == f.windowTitle }) ?? windows.first {
            if !w.minimized, let r = frame(of: w.element) { return (r, needsInput) }
            if w.minimized, let item = dock.first(where: { $0.subrole == "AXMinimizedWindowDockItem" && $0.title == w.title }) {
                return (item.frame, needsInput)
            }
        }
        return appItem.map { ($0.frame, needsInput) }
    }

    private static func dockItems() -> [DockItem] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let ax = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        let lists = WindowService.attribute(ax, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return lists.flatMap { WindowService.attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }.compactMap { e in
            guard let r = frame(of: e) else { return nil }
            return DockItem(title: WindowService.attribute(e, kAXTitleAttribute) as? String ?? "",
                            subrole: WindowService.attribute(e, kAXSubroleAttribute) as? String ?? "",
                            url: WindowService.attribute(e, kAXURLAttribute) as? URL, frame: r,
                            badge: WindowService.attribute(e, "AXStatusLabel") as? String ?? "")
        }
    }

    private static func frame(of e: AXUIElement) -> CGRect? {
        guard let p = WindowService.attribute(e, kAXPositionAttribute),
              let s = WindowService.attribute(e, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pos), AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: pos, size: size)
    }
}

private final class LinksPanel: NSPanel {
    let linesView = LinesView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = linesView
    }

    override var canBecomeKey: Bool { false }
}

/// Purple normally, green while the follow-up's app asks for input.
private func linkColor(needsInput: Bool) -> NSColor {
    needsInput ? NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.35, alpha: 1)
               : NSColor(calibratedRed: 0.40, green: 0.28, blue: 0.95, alpha: 1)
}

private final class LinesView: NSView {
    /// Line segments in global Cocoa coordinates; green while their app needs input.
    var lines: [(from: NSPoint, to: NSPoint, needsInput: Bool)] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let o = window?.frame.origin, !lines.isEmpty else { return }
        for needsInput in [false, true] {
            linkColor(needsInput: needsInput).withAlphaComponent(0.85).set()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            for (a, b, n) in lines where n == needsInput {
                path.move(to: NSPoint(x: a.x - o.x, y: a.y - o.y))
                path.line(to: NSPoint(x: b.x - o.x, y: b.y - o.y))
            }
            path.stroke()
        }
    }
}

/// Small clickable ring at the end of a line; clicking it opens its follow-up, right-clicking removes it.
private final class RingPanel: NSPanel {
    static let size: CGFloat = 16
    var followUp: FollowUp? { didSet { updateTip() } }
    var needsInput = false {
        didSet {
            guard needsInput != oldValue else { return }
            (contentView as? RingView)?.needsInput = needsInput
            updateTip()
        }
    }
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    private let tip = TipPanel()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = RingView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.onClick = { [weak self] in self?.onClick?() }
        view.onRightClick = { [weak self] in self?.onRightClick?() }
        view.onHover = { [weak self] in self?.showTip($0) }
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    override func orderOut(_ sender: Any?) {
        tip.orderOut(nil)
        super.orderOut(sender)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        if tip.isVisible { placeTip() }
    }

    private func showTip(_ show: Bool) {
        guard show, followUp != nil else { tip.orderOut(nil); return }
        updateTip() // refresh "marked … ago"
        placeTip()
        tip.orderFrontRegardless()
    }

    /// "3 · Slack", then what was marked there (chat, page, document) and when.
    private func updateTip() {
        guard let f = followUp else { return }
        let number = FollowUpStore.shared.number(of: f).map { "\($0) · " } ?? ""
        var detail: [String] = []
        if f.label != f.appName { detail.append(f.label.count > 70 ? f.label.prefix(69) + "…" : f.label) }
        detail.append("marked " + RingPanel.ago.localizedString(for: f.created, relativeTo: Date()))
        if needsInput { detail.append("waiting for your input") }
        tip.set(title: number + f.appName, detail: detail)
    }

    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// Centered just above the ring.
    private func placeTip() {
        let s = tip.frame.size
        tip.setFrameOrigin(NSPoint(x: frame.midX - s.width / 2, y: frame.maxY + 2))
    }
}

/// Small dark label shown above a hovered ring: a bold title line, then lighter detail lines.
private final class TipPanel: NSPanel {
    private let field = NSTextField(labelWithString: "")

    func set(title: String, detail: [String]) {
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white])
        for line in detail {
            text.append(NSAttributedString(string: "\n" + line, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.75)]))
        }
        field.attributedStringValue = text
        let size = field.intrinsicContentSize
        setContentSize(NSSize(width: ceil(size.width) + 16, height: ceil(size.height) + 10))
        field.frame = NSRect(x: 8, y: 5, width: ceil(size.width), height: ceil(size.height))
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        bg.layer?.cornerRadius = 5
        bg.addSubview(field)
        contentView = bg
    }

    override var canBecomeKey: Bool { false }
}

private final class RingView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    /// While true the ring pulses slowly (grows and fades, ~1.6 s per beat).
    var needsInput = false {
        didSet {
            needsDisplay = true
            pulse?.invalidate()
            pulse = nil
            guard needsInput else { return }
            let start = CACurrentMediaTime()
            pulse = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.phase = (1 - cos((CACurrentMediaTime() - start) * 2 * .pi / 1.6)) / 2
            }
        }
    }
    private var pulse: Timer?
    /// 0…1 position in the pulse.
    private var phase: CGFloat = 0 { didSet { needsDisplay = true } }
    deinit { pulse?.invalidate() }
    private var hovered = false { didSet { needsDisplay = true; onHover?(hovered) } }

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
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hovered = false
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Nearly invisible fill so clicks in the ring's hole still land on it.
        NSColor.black.withAlphaComponent(0.01).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let p = needsInput && !hovered ? phase : 0
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 3 - 1.5 * p, dy: 3 - 1.5 * p))
        ring.lineWidth = hovered ? 3 : 2
        linkColor(needsInput: needsInput).withAlphaComponent(hovered ? 1 : 0.9 - 0.5 * p).setStroke()
        ring.stroke()
    }
}
