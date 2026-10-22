import AppKit

/// Read-only overview of every saved follow-up; unlike the radial picker it never truncates.
final class JobsListView: NSView {
    let heading = NSTextField(labelWithString: "")
    let scrollView = NSScrollView()
    private(set) var buttons: [NSButton] = []
    var onOpen: ((FollowUp) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private let items: [FollowUp]

    override var isFlipped: Bool { true }

    init(items: [FollowUp], width: CGFloat, maxHeight: CGFloat) {
        self.items = items
        let rowHeight: CGFloat = 54
        let headerHeight: CGFloat = 44
        let height = min(maxHeight, headerHeight + max(42, CGFloat(items.count) * rowHeight) + 10)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        heading.stringValue = items.isEmpty ? "No linked jobs" : "Linked jobs · \(items.count)"
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.frame = NSRect(x: 16, y: 13, width: width - 32, height: 22)
        addSubview(heading)

        scrollView.frame = NSRect(x: 8, y: headerHeight, width: width - 16, height: height - headerHeight - 8)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        let document = FlippedJobsDocument(frame: NSRect(x: 0, y: 0, width: width - 32,
                                                         height: max(42, CGFloat(items.count) * rowHeight)))
        for (index, item) in items.enumerated() {
            let button = NSButton(title: "\(index + 1). \(item.appName)\n\(item.label)", target: nil, action: #selector(openJob(_:)))
            button.target = self
            button.tag = index
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 13)
            button.cell?.wraps = true
            button.cell?.lineBreakMode = .byTruncatingTail
            button.frame = NSRect(x: 6, y: CGFloat(index) * rowHeight, width: width - 48, height: rowHeight - 4)
            button.toolTip = "\(index + 1). \(item.appName) — \(item.label)"
            document.addSubview(button)
            buttons.append(button)
        }
        if items.isEmpty {
            let hint = NSTextField(labelWithString: "Middle-click inside an app to add one.")
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: 12)
            hint.frame = NSRect(x: 8, y: 8, width: width - 48, height: 22)
            document.addSubview(hint)
        }
        scrollView.documentView = document
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    @objc private func openJob(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onOpen?(items[sender.tag])
    }
}

private final class FlippedJobsDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Non-activating hover panel: does not steal focus from the user's current application.
final class JobsHoverController {
    private var panel: NSPanel?
    private weak var anchor: DView?
    private var items: [FollowUp] = []
    private var pending: DispatchWorkItem?
    var onOpen: ((FollowUp) -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func hover(_ inside: Bool, anchor: DView, items: [FollowUp]) {
        self.anchor = anchor
        self.items = items
        pending?.cancel()
        if inside {
            guard !isVisible else { return }
            let work = DispatchWorkItem { [weak self] in self?.show() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            scheduleDismiss()
        }
    }

    func update(items: [FollowUp]) {
        self.items = items
        if isVisible { show() }
    }

    func close() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func scheduleDismiss() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            if self.anchor?.window?.frame.contains(p) == true || self.panel?.frame.contains(p) == true { return }
            self.close()
        }
        pending = work
        // Allows crossing the small gap between D and the list without it vanishing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func show() {
        guard let anchor, let anchorWindow = anchor.window, anchorWindow.isVisible,
              let screen = anchorWindow.screen ?? NSScreen.main else { return }
        let safe = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(420, safe.width)
        let content = JobsListView(items: items, width: width, maxHeight: min(420, safe.height))
        content.onOpen = { [weak self] item in
            guard let self else { return }
            self.close()
            self.onOpen?(item)
        }
        content.onHoverChanged = { [weak self] inside in
            if inside { self?.pending?.cancel() } else { self?.scheduleDismiss() }
        }
        let box = NSVisualEffectView(frame: content.frame)
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.masksToBounds = true
        box.addSubview(content)

        let popup = panel ?? NSPanel(contentRect: content.frame,
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        popup.isReleasedWhenClosed = false
        popup.level = .statusBar
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = true
        popup.hidesOnDeactivate = false
        popup.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        popup.contentView = box
        let d = anchorWindow.frame
        let x = min(max(d.maxX - width, safe.minX), safe.maxX - width)
        let below = d.minY - content.frame.height - 4
        let y = below >= safe.minY ? below : min(d.maxY + 4, safe.maxY - content.frame.height)
        popup.setFrame(NSRect(x: x, y: max(safe.minY, y), width: width, height: content.frame.height), display: true)
        panel = popup
        popup.orderFrontRegardless()
    }
}
