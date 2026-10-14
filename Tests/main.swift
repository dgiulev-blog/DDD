import AppKit

func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("FAIL: \(description)") }
    print("PASS: \(description)")
}

func followUp(_ bundle: String = "com.example.app", title: String = "Window", url: String? = nil,
              selection: String? = nil) -> FollowUp {
    FollowUp(bundleID: bundle, appName: "Example", label: "Example", windowTitle: title,
             url: url, selection: selection)
}

let a = followUp(url: "https://example.org/one")
expect(a.samePlace(as: followUp(title: "Changed", url: "https://example.org/one")), "URL identity ignores changed title")
expect(!a.samePlace(as: followUp(url: "https://example.org/two")), "Different URLs remain separate")
expect(!a.samePlace(as: followUp("com.example.other", url: "https://example.org/one")), "Identity includes app")
expect(followUp(selection: "Chat A").samePlace(as: followUp(selection: "Chat A")), "Native selection identity")
expect(!followUp(selection: "Chat A").samePlace(as: followUp(selection: "Chat B")), "Different chats remain separate")
expect(!followUp(title: "One").samePlace(as: followUp(title: "Two")), "Different windows remain separate")
expect(FollowUpCapture.clean(" \u{200E}Example\u{2069} ") == "Example", "Direction marks and whitespace cleaned")
let encoded = try JSONEncoder().encode(a)
let decoded = try JSONDecoder().decode(FollowUp.self, from: encoded)
expect(decoded.id == a.id && decoded.samePlace(as: a), "Follow-up Codable round trip")
expect(Machine(name: "Example", host: "192.0.2.1", os: "macOS", online: true).vncURL?.absoluteString == "vnc://192.0.2.1", "VNC URL construction")
expect(AppCategory(bundleID: "com.apple.Safari", bundleURL: nil) == .browser, "Browser categorization")
expect(AppCategory(bundleID: "com.apple.mail", bundleURL: nil) == .communication, "Communication categorization")
expect(AppCategory(bundleID: nil, bundleURL: nil) == .other, "Unknown app categorization")
let safe = NSRect(x: 0, y: 0, width: 1440, height: 900)
for hub in [NSPoint(x: 720, y: 450), NSPoint(x: 50, y: 50), NSPoint(x: 1390, y: 850)] {
    for count in [0, 1, 6, 15, 30] {
        let spots = RadialView.ringTargets(count: count, hub: hub, safe: safe)
        expect(spots.count == count, "Radial layout count \(count) at \(hub)")
        expect(spots.allSatisfy { safe.insetBy(dx: 44, dy: 46).contains($0) }, "Radial targets inside safe area")
    }
}
_ = NSApplication.shared
let panel = DPanel()
expect(panel.frame.size == NSSize(width: 52, height: 52), "Native D panel geometry")
expect(!panel.canBecomeKey && !panel.isOpaque, "Non-activating transparent D panel")
let radial = RadialView(frame: safe, hub: NSPoint(x: 720, y: 450), safe: safe, apps: [])
expect(radial.acceptsFirstResponder, "Native radial view accepts Escape key handling")
expect(radial.bubbleCenters.isEmpty, "Empty app list creates no phantom bubbles")
panel.orderOut(nil)
print("All core and native UI construction checks passed. No DDD preferences or follow-up store accessed.")
