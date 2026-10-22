import AppKit

/// The small always-on-top "D" button.
final class DPanel: NSPanel {
    let dView = DView(frame: NSRect(x: 0, y: 0, width: 52, height: 52))

    init() {
        super.init(contentRect: dView.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false // we move it ourselves so a click vs. drag can be told apart
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = dView
    }

    override var canBecomeKey: Bool { false }
}

final class DView: NSView {
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    private var downPoint = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downPoint.x, dy = p.y - downPoint.y
        if !dragging {
            guard hypot(dx, dy) >= 3 else { return }
            dragging = true
            onDragBegan?()
        }
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            onMoved?(window?.frame.origin ?? .zero)
        } else {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Nearly invisible disc so clicks inside the D's hole still land on us
        // (fully transparent pixels would pass clicks through to the window below).
        NSColor.black.withAlphaComponent(0.01).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).fill()

        // Just the letter: white fill with a colored outline so it reads on any background.
        let fontSize: CGFloat = 38
        let base = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .strokeColor: NSColor(calibratedRed: 0.40, green: 0.28, blue: 0.95, alpha: 1),
            .strokeWidth: -5, // negative = fill and stroke
        ]
        let s = "D" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)

        if count > 0 { drawBadge("\(count)", in: bounds) }
    }

    /// Number of open follow-ups, shown as a red badge in the top-right corner.
    var count = 0 { didSet { needsDisplay = true } }
}

/// Red count badge anchored to the top-right of `rect`.
func drawBadge(_ label: String, in rect: NSRect) {
    let text = label as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold),
                                                .foregroundColor: NSColor.white]
    let size = text.size(withAttributes: attrs)
    let w = max(18, size.width + 8)
    let badge = NSRect(x: rect.maxX - w, y: rect.maxY - 18, width: w, height: 18)
    NSColor.systemRed.setFill()
    NSBezierPath(roundedRect: badge, xRadius: 9, yRadius: 9).fill()
    text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attrs)
}
