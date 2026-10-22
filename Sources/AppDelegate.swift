import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dPanel = DPanel()
    private var overlay: OverlayPanel?
    private let defaults = UserDefaults.standard
    private let middleClick = MiddleClickMonitor()
    private let links = LinksOverlay()
    private let jobsHover = JobsHoverController()
    private let captureQueue = DispatchQueue(label: "io.prim.ddd.capture", qos: .userInitiated)

    private var isOn: Bool {
        get { defaults.object(forKey: "isOn") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isOn") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one DDD: a second launch quits right away.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0 != me }) {
            NSApp.terminate(nil)
            return
        }
        // Open at login by default (once, so turning it off in the menu or System Settings sticks).
        if !defaults.bool(forKey: "loginItemRegistered") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "loginItemRegistered")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        dPanel.dView.onClick = { [weak self] in self?.toggleOverlay() }
        dPanel.dView.onDragBegan = { [weak self] in
            self?.jobsHover.close()
            self?.closeOverlay()
        }
        dPanel.dView.onHoverChanged = { [weak self] inside in
            guard let self, self.isOn, self.overlay == nil else { return }
            self.jobsHover.hover(inside, anchor: self.dPanel.dView, items: FollowUpStore.shared.items)
        }
        jobsHover.onOpen = { [weak self] item in
            self?.closeOverlay()
            FollowUpOpener.open(item)
        }
        jobsHover.onRemove = { item in FollowUpStore.shared.remove(item) }
        dPanel.dView.onMoved = { [weak self] origin in
            self?.defaults.set(NSStringFromPoint(origin), forKey: "dOrigin")
        }
        dPanel.setFrameOrigin(initialOrigin())
        links.hub = { [weak self] in
            guard let f = self?.dPanel.frame else { return .zero }
            return NSPoint(x: f.midX, y: f.midY)
        }
        links.onOpen = { [weak self] in self?.closeOverlay() }
        NotificationCenter.default.addObserver(self, selector: #selector(dMoved),
                                               name: NSWindow.didMoveNotification, object: dPanel)

        NotificationCenter.default.addObserver(self, selector: #selector(appResigned),
                                               name: NSApplication.didResignActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(followUpsChanged),
                                               name: FollowUpStore.didChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)

        applyState()
        followUpsChanged()
        MachineService.shared.start()
        if !WindowService.isTrusted { WindowService.promptForTrust() }

        middleClick.onMiddleClick = { [weak self] point in self?.markFollowUp(at: point) }
        startMiddleClick()
    }

    // MARK: Follow-ups

    /// The event tap needs Accessibility permission; keep trying until it is granted.
    private func startMiddleClick() {
        guard !middleClick.start() else {
            NSLog("DDD middle-click listening")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startMiddleClick() }
    }

    private func markFollowUp(at point: CGPoint) {
        captureQueue.async {
            let captured = FollowUpCapture.capture(at: point)
            DispatchQueue.main.async {
                guard let f = captured else {
                    Toast.show("Can't identify this spot — try the workspace row in Orca", near: point)
                    return
                }
                let result = FollowUpStore.shared.toggle(f)
                let total = FollowUpStore.shared.items.count
                Toast.show(result.added ? "\(result.number)  ·  \(f.label)"
                                        : "✓ \(f.label) — done, \(total) left", near: point)
            }
        }
    }

    @objc private func followUpsChanged() {
        let count = FollowUpStore.shared.items.count
        dPanel.dView.count = count
        jobsHover.update(items: FollowUpStore.shared.items)
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.imagePosition = .imageLeft
        links.refresh()
    }

    @objc private func dMoved() {
        jobsHover.close()
        links.redraw()
    }

    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            FollowUpCapture.enableWebAccessibility(for: app)
        }
    }

    // MARK: Menu bar icon

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let toggle = NSMenuItem(title: "Show D", action: #selector(toggleOn), keyEquivalent: "")
            toggle.target = self
            toggle.state = isOn ? .on : .off
            menu.addItem(toggle)
            let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
            if !WindowService.isTrusted {
                let grant = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(grantAccess), keyEquivalent: "")
                grant.target = self
                menu.addItem(grant)
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit DDD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleOn()
        }
    }

    @objc private func toggleOn() {
        isOn.toggle()
        applyState()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    @objc private func grantAccess() {
        WindowService.promptForTrust()
        WindowService.openAccessibilitySettings()
    }

    private func applyState() {
        let image = NSImage(systemSymbolName: isOn ? "d.circle.fill" : "d.circle", accessibilityDescription: "DDD")
        image?.isTemplate = true
        statusItem.button?.image = image
        if isOn {
            links.start()
            dPanel.orderFrontRegardless() // keep the D above the lines
        } else {
            jobsHover.close()
            closeOverlay()
            links.stop()
            dPanel.orderOut(nil)
        }
    }

    private func initialOrigin() -> NSPoint {
        if let s = defaults.string(forKey: "dOrigin") {
            let p = NSPointFromString(s)
            let probe = NSRect(origin: p, size: dPanel.frame.size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(probe) }) { return p }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: vf.maxX - 90, y: vf.maxY - 90)
    }

    /// A display was unplugged or rearranged: bring the D back if it is no longer on any screen.
    @objc private func screensChanged() {
        jobsHover.close()
        links.rebuildPanels()
        if isOn { dPanel.orderFrontRegardless() }
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(dPanel.frame) }) else { return }
        closeOverlay()
        dPanel.setFrameOrigin(initialOrigin())
    }

    // MARK: Rays overlay

    private func toggleOverlay() {
        jobsHover.close()
        overlay == nil ? showOverlay() : closeOverlay()
    }

    private func showOverlay() {
        let d = dPanel.frame
        let dCenter = NSPoint(x: d.midX, y: d.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(dCenter) }) ?? NSScreen.main else { return }
        let sf = screen.frame
        let hub = NSPoint(x: dCenter.x - sf.minX, y: dCenter.y - sf.minY)
        let safe = screen.visibleFrame.offsetBy(dx: -sf.minX, dy: -sf.minY)

        MachineService.shared.refresh()
        let panel = OverlayPanel(screen: screen)
        let view = RadialView(frame: NSRect(origin: .zero, size: sf.size), hub: hub, safe: safe,
                              apps: WindowService.runningApps(),
                              aims: links.aims.mapValues { NSPoint(x: $0.x - sf.minX, y: $0.y - sf.minY) })
        view.onDismiss = { [weak self] in self?.closeOverlay() }
        view.onPick = { [weak self] app, window in
            self?.closeOverlay()
            WindowService.focus(app, window: window)
        }
        panel.contentView = view
        overlay = panel

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        links.starts = view.bubbleCenters.mapValues { NSPoint(x: $0.x + sf.minX, y: $0.y + sf.minY) }
        links.bringToFront() // lines from the numbered apps, above the ring's dimmed backdrop
        dPanel.orderFrontRegardless() // keep the D above the rays
    }

    private func closeOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
        links.starts = nil
    }

    @objc private func appResigned() {
        closeOverlay()
    }
}
