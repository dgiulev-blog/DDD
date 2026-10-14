import AppKit
import ApplicationServices
import UniformTypeIdentifiers

let screenSharingBundleID = "com.apple.ScreenSharing"

struct AppEntry {
    let app: NSRunningApplication?
    let bundleID: String?
    let bundleURL: URL?
    private let fallbackName: String

    init(running: NSRunningApplication) {
        app = running
        bundleID = running.bundleIdentifier
        bundleURL = running.bundleURL
        fallbackName = running.localizedName ?? "App"
    }

    /// An app that is not running (shown grayed out).
    init?(notRunningBundleID id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        app = nil
        bundleID = id
        bundleURL = url
        fallbackName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var category: AppCategory { AppCategory(bundleID: bundleID, bundleURL: bundleURL) }
    var isRunning: Bool { app != nil }
    var isScreenSharing: Bool { bundleID == screenSharingBundleID }
    var name: String { app?.localizedName ?? fallbackName }
    var icon: NSImage {
        if let icon = app?.icon { return icon }
        if let url = bundleURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// Groups apps by type so related apps sit next to each other in the ring (declaration order = ring order).
enum AppCategory: Int, Comparable {
    case browser, communication, productivity, developer, media, utilities, other

    private static let communicationIDs: Set<String> = [
        "com.tinyspeck.slackmacgap", "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.apple.mail", "com.microsoft.Outlook",
    ]

    init(bundleID: String?, bundleURL: URL?) {
        if let id = bundleID {
            if BrowserTheme.browserIDs.contains(id) { self = .browser; return }
            if Self.communicationIDs.contains(id) { self = .communication; return }
        }
        let type = bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        switch type?.replacingOccurrences(of: "public.app-category.", with: "") {
        case "social-networking": self = .communication
        case "productivity", "business", "finance", "education", "reference", "lifestyle": self = .productivity
        case "developer-tools": self = .developer
        case "graphics-design", "photography", "video", "music", "entertainment", "games", "news": self = .media
        case "utilities": self = .utilities
        default: self = .other
        }
    }

    static func < (a: AppCategory, b: AppCategory) -> Bool { a.rawValue < b.rawValue }
}

struct WindowEntry {
    let element: AXUIElement
    let title: String
    let minimized: Bool

    /// CGWindowID of this window (private but long-stable AX SPI).
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Screen Sharing first (always present, even when not running), then regular running apps that have
    /// a window, grouped by type, oldest launch first within each group. Apps with follow-ups stay in
    /// even without a window (grayed when closed).
    static func runningApps() -> [AppEntry] {
        let followUpIDs = Set(FollowUpStore.shared.items.map(\.bundleID))
        var list = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }
            // Without Accessibility access no windows can be read, so keep everything rather than nothing.
            .filter { !isTrusted || $0.bundleIdentifier == screenSharingBundleID
                || followUpIDs.contains($0.bundleIdentifier ?? "") || !windows(of: AppEntry(running: $0)).isEmpty }
            .map { running -> (entry: AppEntry, category: AppCategory, launched: Date) in
                let entry = AppEntry(running: running)
                return (entry, entry.category, running.launchDate ?? .distantPast)
            }
        let runningIDs = Set(list.compactMap(\.entry.bundleID))
        for id in followUpIDs.subtracting(runningIDs) {
            if let entry = AppEntry(notRunningBundleID: id) { list.append((entry, entry.category, .distantFuture)) }
        }
        var apps = list
            .sorted { ($0.category, $0.launched) < ($1.category, $1.launched) }
            .map(\.entry)
        if let i = apps.firstIndex(where: \.isScreenSharing) {
            apps.insert(apps.remove(at: i), at: 0)
        } else if let ss = AppEntry(notRunningBundleID: screenSharingBundleID) {
            apps.insert(ss, at: 0)
        }
        return apps
    }

    /// Windows of an app, oldest first (window IDs are assigned in creation order).
    static func windows(of entry: AppEntry) -> [WindowEntry] {
        guard let running = entry.app else { return [] }
        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard let list = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return list.compactMap { w in
            let subrole = attribute(w, kAXSubroleAttribute) as? String
            guard subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            let title = (attribute(w, kAXTitleAttribute) as? String) ?? ""
            let minimized = (attribute(w, kAXMinimizedAttribute) as? Bool) ?? false
            return WindowEntry(element: w, title: title, minimized: minimized)
        }
        .sorted { ($0.windowID ?? .max) < ($1.windowID ?? .max) }
    }

    /// Bring the app forward (launching it if needed) and, if given, restore + raise that specific window.
    static func focus(_ entry: AppEntry, window: WindowEntry?) {
        guard let running = entry.app else {
            if let url = entry.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        if running.isHidden { running.unhide() }
        if let w = window {
            if w.minimized {
                AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        }
        NSApp.yieldActivation(to: running)
        running.activate()
        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Some apps re-order their windows on activation, and some ignore un-minimizing while in the
        // background: once it settles (after the Dock animation for minimized windows), restore and raise again.
        if let w = window {
            DispatchQueue.main.asyncAfter(deadline: .now() + (w.minimized ? 0.35 : 0.08)) {
                if attribute(w.element, kAXMinimizedAttribute) as? Bool == true {
                    AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
            }
        }
    }

    /// Close one window by pressing its close button (the app may still ask to save).
    static func close(_ window: WindowEntry) {
        guard let button = attribute(window.element, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
}
