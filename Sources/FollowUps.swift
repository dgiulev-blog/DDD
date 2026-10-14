import AppKit
import ApplicationServices

/// A remembered place inside an app that still needs attention.
struct FollowUp: Codable {
    var id = UUID()
    let bundleID: String
    let appName: String
    let label: String
    let windowTitle: String
    /// Page URL for browsers and web-based apps (Slack, Claude, Notion, …).
    let url: String?
    /// Selected item (e.g. chat name) for native apps without a URL.
    let selection: String?
    var created = Date()

    /// Same place = same app and same URL, or same window title + selected item.
    func samePlace(as o: FollowUp) -> Bool {
        guard bundleID == o.bundleID else { return false }
        if let url, let other = o.url { return url == other }
        return windowTitle == o.windowTitle && selection == o.selection
    }
}

/// Follow-ups in creation order; a follow-up's number is its position (1-based), so numbers close up on removal.
final class FollowUpStore {
    static let shared = FollowUpStore()
    static let didChange = Notification.Name("DDDFollowUpsChanged")
    private(set) var items: [FollowUp] = []

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DDD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("followups.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([FollowUp].self, from: data) {
            items = list
        }
    }

    func number(of f: FollowUp) -> Int? { items.firstIndex { $0.id == f.id }.map { $0 + 1 } }
    func items(for bundleID: String?) -> [FollowUp] { items.filter { $0.bundleID == bundleID } }

    /// Adds the follow-up, or removes the existing one for the same place.
    func toggle(_ f: FollowUp) -> (number: Int, added: Bool) {
        if let i = items.firstIndex(where: { $0.samePlace(as: f) }) {
            items.remove(at: i)
            save()
            return (i + 1, false)
        }
        items.append(f)
        save()
        return (items.count, true)
    }

    func remove(_ f: FollowUp) {
        items.removeAll { $0.id == f.id }
        save()
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: file, options: .atomic)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

// MARK: - Capture

enum FollowUpCapture {
    /// Chromium/Electron apps only build their web accessibility tree when asked to.
    static func enableWebAccessibility(for app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        let isElectron = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        guard isElectron || BrowserTheme.browserIDs.contains(app.bundleIdentifier ?? "") else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Describe the place under `point` (global, top-left origin). Nil for our own windows or no window.
    static func capture(at point: CGPoint) -> FollowUp? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              let window = window(of: hit) else { return nil }
        return describe(window: window, of: app)
    }

    static func describe(window: AXUIElement, of app: NSRunningApplication) -> FollowUp? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        enableWebAccessibility(for: app)

        let appName = clean(app.localizedName ?? "App")
        let windowTitle = clean(WindowService.attribute(window, kAXTitleAttribute) as? String ?? "")
        let isSlack = bundleID == "com.tinyspeck.slackmacgap"
        let scan = scanWindow(window, findSlackChannel: isSlack)
        var url = (WindowService.attribute(window, kAXDocumentAttribute) as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }
        url = url ?? scan.webURL
        // Slack's URL doesn't always name the open conversation (e.g. ".../activity-inbox"); its message list does.
        if isSlack, let channel = scan.slackChannel, let u = url.flatMap(URL.init(string:)) {
            let parts = u.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "client" { url = "https://app.slack.com/client/\(parts[1])/\(channel)" }
        }

        // Window titles usually end in " - AppName"; the part before it names the place.
        var title = windowTitle
        if let r = title.range(of: " - \(appName)") { title = String(title[..<r.lowerBound]) }
        // For web pages the URL is enough; app-internal addresses (file://…#/session) also keep the selected tab.
        let selection = url?.hasPrefix("http") == true ? nil : scan.selection
        let label = selection
            ?? (!title.isEmpty && title != appName ? title : nil)
            ?? scan.webTitle.flatMap { $0 != appName ? $0 : nil } ?? scan.firstPrompt ?? url ?? appName

        return FollowUp(bundleID: bundleID, appName: appName, label: label, windowTitle: windowTitle,
                        url: url, selection: selection)
    }

    private static func window(of element: AXUIElement) -> AXUIElement? {
        if let w = axElement(WindowService.attribute(element, kAXWindowAttribute)) { return w }
        var e: AXUIElement? = element
        while let cur = e {
            if WindowService.attribute(cur, kAXRoleAttribute) as? String == kAXWindowRole { return cur }
            e = axElement(WindowService.attribute(cur, kAXParentAttribute))
        }
        return nil
    }

    /// One pass over the window: first web page URL/title, and the deepest selected item's text.
    private static func scanWindow(_ window: AXUIElement, findSlackChannel: Bool)
        -> (webURL: String?, webTitle: String?, selection: String?, slackChannel: String?, firstPrompt: String?) {
        var webURL: String?, webTitle: String?, selection: String?, selectionDepth = -1, slackChannel: String?
        var firstPrompt: String?
        walk(window, maxNodes: findSlackChannel ? 8000 : 4000) { e, depth in
            let role = WindowService.attribute(e, kAXRoleAttribute) as? String ?? ""
            if findSlackChannel, slackChannel == nil, role == "AXGroup",
               let id = WindowService.attribute(e, "AXDOMIdentifier") as? String, id.hasPrefix("message-list_"),
               let channel = id.split(separator: ".").last {
                slackChannel = String(channel)
            }
            if webURL == nil, role == "AXWebArea",
               let u = (WindowService.attribute(e, kAXURLAttribute) as? URL)?.absoluteString,
               u.hasPrefix("http") || u.contains("#/") { // "#/…" = in-app route, e.g. Hermes sessions
                webURL = u
                webTitle = (WindowService.attribute(e, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            // AI chats (Claude, …): the first "You said: …" heading names the thread.
            if firstPrompt == nil, role == "AXHeading", let t = text(of: e, whole: true), t.hasPrefix("You said: ") {
                firstPrompt = String(t.dropFirst("You said: ".count).prefix(80))
            }
            if depth >= selectionDepth, WindowService.attribute(e, kAXSelectedAttribute) as? Bool == true,
               ["AXRow", "AXCell", "AXStaticText", "AXGroup", "AXRadioButton"].contains(role), let text = text(of: e) {
                selection = text
                selectionDepth = depth
            }
            return true
        }
        return (webURL, webTitle, selection, slackChannel, firstPrompt)
    }

    /// Visible text of an element or its first children; "Name, last message, date" is cut to "Name".
    static func text(of e: AXUIElement, whole: Bool = false) -> String? {
        let own = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] // description before value: list cells keep the name there, the preview in value
            .compactMap { WindowService.attribute(e, $0) as? String }.first { !$0.isEmpty }
        let kids = (WindowService.attribute(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(4)
        guard let raw = own ?? kids.lazy.compactMap({ text(of: $0) }).first else { return nil }
        var name = clean(whole ? raw : raw.components(separatedBy: ", ").first ?? raw)
        if name.hasSuffix(" Close") { name = String(name.dropLast(" Close".count)) } // tab titles include their close button
        return name.isEmpty ? nil : name
    }

    /// Drops invisible direction marks/isolates that apps like WhatsApp and Telegram wrap names in.
    static func clean(_ s: String) -> String {
        let invisible = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { !invisible.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }
}

func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// Depth-first walk of an accessibility tree; `visit` returns false to stop.
func walk(_ root: AXUIElement, maxNodes: Int, maxDepth: Int = 40, visit: (AXUIElement, Int) -> Bool) {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    var count = 0
    while let (e, depth) = stack.popLast(), count < maxNodes {
        count += 1
        guard visit(e, depth) else { return }
        if depth < maxDepth, let kids = WindowService.attribute(e, kAXChildrenAttribute) as? [AXUIElement] {
            stack.append(contentsOf: kids.reversed().map { ($0, depth + 1) })
        }
    }
}

// MARK: - Reopen

enum FollowUpOpener {
    static func open(_ f: FollowUp, launchIfNeeded: Bool = true) {
        let deep = deepLink(f)
        let isBrowser = BrowserTheme.browserIDs.contains(f.bundleID)
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: f.bundleID).first else {
            if let deep { NSWorkspace.shared.open(deep); return }
            guard launchIfNeeded, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: f.bundleID) else { return }
            if isBrowser, let u = f.url.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open([u], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                return
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { open(f, launchIfNeeded: false) }
            }
            return
        }

        let entry = AppEntry(running: running)
        let windows = WindowService.windows(of: entry)

        if isBrowser, let url = f.url {
            if let (window, tab) = findTab(titled: f.label, in: windows) {
                AXUIElementPerformAction(tab, kAXPressAction as CFString)
                WindowService.focus(entry, window: window)
            } else if let u = URL(string: url), let appURL = running.bundleURL {
                NSWorkspace.shared.open([u], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }

        let window = windows.first { $0.title == f.windowTitle } ?? windows.first
        WindowService.focus(entry, window: window)
        if let deep {
            NSWorkspace.shared.open(deep)
        } else if let sel = f.selection ?? (f.label != f.appName ? f.label : nil), let window {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reselect(sel, in: window.element) }
        }
    }

    /// App URL schemes that jump straight to the captured place.
    private static func deepLink(_ f: FollowUp) -> URL? {
        if f.bundleID == "com.apple.MobileSMS" {
            let handle = f.windowTitle.replacingOccurrences(of: " ", with: "")
            let isHandle = handle.contains("@") || (handle.count > 5 && handle.allSatisfy { "+0123456789".contains($0) })
            return isHandle ? URL(string: "imessage://\(handle)") : nil
        }
        guard let s = f.url, let u = URL(string: s), let host = u.host else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" }
        switch f.bundleID {
        // Only real channel/DM IDs (C…, D…, G…); views like "activity-inbox" would break Slack.
        case "com.tinyspeck.slackmacgap" where host == "app.slack.com" && parts.count >= 3 && parts[0] == "client"
            && parts[2].range(of: "^[CDG][A-Z0-9]{8,}$", options: .regularExpression) != nil:
            return URL(string: "slack://channel?team=\(parts[1])&id=\(parts[2])")
        case "com.anthropic.claudefordesktop" where host == "claude.ai":
            return URL(string: "claude://claude.ai\(u.path)")
        case "notion.id" where host.hasSuffix("notion.so"):
            return URL(string: "notion://\(host)\(u.path)")
        default:
            return nil
        }
    }

    /// Browser tab whose title starts with the page title (Chromium/Safari tabs are AXRadioButtons).
    private static func findTab(titled title: String, in windows: [WindowEntry]) -> (WindowEntry, AXUIElement)? {
        for w in windows {
            var found: AXUIElement?
            walk(w.element, maxNodes: 1500, maxDepth: 14) { e, _ in
                if WindowService.attribute(e, kAXRoleAttribute) as? String == "AXRadioButton",
                   let t = WindowService.attribute(e, kAXTitleAttribute) as? String, t.hasPrefix(title) {
                    found = e
                    return false
                }
                return true
            }
            if let found { return (w, found) }
        }
        return nil
    }

    /// Select the list item (e.g. a chat) whose text starts with `selection`.
    private static func reselect(_ selection: String, in window: AXUIElement) {
        var target: AXUIElement?
        walk(window, maxNodes: 4000) { e, _ in
            let role = WindowService.attribute(e, kAXRoleAttribute) as? String ?? ""
            if ["AXStaticText", "AXCell", "AXRow", "AXButton", "AXRadioButton"].contains(role),
               let t = FollowUpCapture.text(of: e), t.hasPrefix(selection) {
                target = e
                return false
            }
            return true
        }
        guard let target else { return }

        // Prefer a real "press" on the item or one of its containers.
        var e: AXUIElement? = target
        for _ in 0..<5 {
            guard let cur = e else { break }
            var names: CFArray?
            if AXUIElementCopyActionNames(cur, &names) == .success,
               (names as? [String])?.contains(kAXPressAction) == true,
               AXUIElementPerformAction(cur, kAXPressAction as CFString) == .success { return }
            if WindowService.attribute(cur, kAXRoleAttribute) as? String == "AXRow",
               AXUIElementSetAttributeValue(cur, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return }
            e = axElement(WindowService.attribute(cur, kAXParentAttribute))
        }

        // Fall back to clicking its center, then put the pointer back.
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeRef) == .success,
              AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return }
        let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let back = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let back { CGWarpMouseCursorPosition(back) }
    }
}
