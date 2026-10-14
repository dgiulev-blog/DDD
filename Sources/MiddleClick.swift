import AppKit

/// Intercepts the middle mouse button system-wide (the click is swallowed, not passed to the app).
final class MiddleClickMonitor {
    var onMiddleClick: ((CGPoint) -> Void)?
    private var tap: CFMachPort?

    /// Returns false until Accessibility permission is granted.
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                Unmanaged<MiddleClickMonitor>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return Unmanaged.passUnretained(event) }
        if type == .otherMouseDown {
            let p = event.location
            DispatchQueue.main.async { self.onMiddleClick?(p) }
        }
        return nil
    }
}

/// Short-lived label near the pointer confirming a follow-up was added or removed.
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String, near cgPoint: CGPoint) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: min(label.frame.width + 24, 420), height: 30)
        label.frame = NSRect(x: 12, y: (size.height - label.frame.height) / 2, width: size.width - 24, height: label.frame.height)
        label.lineBreakMode = .byTruncatingTail

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedRed: 0.40, green: 0.28, blue: 0.95, alpha: 0.95).cgColor
        bg.layer?.cornerRadius = 15
        bg.addSubview(label)

        // CG coordinates are top-left based on the primary screen; Cocoa's are bottom-left.
        let primaryH = NSScreen.screens.first?.frame.maxY ?? 0
        let origin = NSPoint(x: cgPoint.x + 14, y: primaryH - cgPoint.y + 10)
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if panel === p { panel = nil }
            })
        }
    }
}
