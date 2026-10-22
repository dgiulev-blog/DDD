import AppKit
import ApplicationServices

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
let jobs = (1...60).map { i in
    FollowUp(bundleID: "com.example.app", appName: "Example", label: "Job \(i)", windowTitle: "Window", url: nil, selection: nil)
}
let jobList = JobsListView(items: jobs, width: 420, maxHeight: 350)
expect(jobList.buttons.count == 60, "Hover list includes every job without truncation")
expect(jobList.buttons.first?.title == "1. Example\nJob 1", "Hover row contains number, app and job label")
expect(jobList.buttons.last?.title == "60. Example\nJob 60", "Last linked job remains reachable")
expect(jobList.scrollView.documentView!.frame.height > jobList.scrollView.frame.height, "Long hover list scrolls")
expect(jobList.frame.height <= 350, "Hover list respects available screen height")
var openedID: UUID?
jobList.onOpen = { openedID = $0.id }
jobList.buttons.last?.performClick(nil)
expect(openedID == jobs.last?.id, "Clicking hover row opens the correct job")
var removedID: UUID?
jobList.onRemove = { removedID = $0.id }
let firstBox = jobList.buttons.first!
expect(firstBox is JobBoxButton, "Every hover job has its own box control")
let rightClick = NSEvent.mouseEvent(with: .rightMouseUp,
    location: firstBox.convert(NSPoint(x: firstBox.bounds.midX, y: firstBox.bounds.midY), to: nil),
    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
openedID = nil
firstBox.rightMouseUp(with: rightClick)
expect(removedID == jobs.first?.id, "Right-click removes only the selected linked job")
expect(openedID == nil, "Right-click never opens the job or activates its app")
let rebuilt = JobsListView(items: Array(jobs.dropFirst()), width: 420, maxHeight: 350)
expect(rebuilt.buttons.count == 59 && rebuilt.buttons.first?.title == "1. Example\nJob 2", "Removal refresh closes numbering gaps")
let emptyList = JobsListView(items: [], width: 420, maxHeight: 350)
expect(emptyList.buttons.isEmpty && emptyList.heading.stringValue == "No linked jobs", "Empty hover state is explicit")
var hoverEvents: [Bool] = []
panel.dView.onHoverChanged = { hoverEvents.append($0) }
panel.dView.updateTrackingAreas()
expect(!panel.dView.trackingAreas.isEmpty, "D tracks pointer entry and exit")
let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
panel.dView.mouseEntered(with: enter)
panel.dView.mouseExited(with: enter)
expect(hoverEvents == [true, false], "D hover signals entry and exit")
let hoverController = JobsHoverController()
panel.setFrameOrigin(NSPoint(x: 180, y: 180))
panel.orderFrontRegardless()
hoverController.hover(true, anchor: panel.dView, items: jobs)
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
expect(hoverController.isVisible, "Hover opens a real non-activating panel after delay")
hoverController.close()
expect(!hoverController.isVisible, "Closing hover panel cancels and hides it")
hoverController.hover(true, anchor: panel.dView, items: jobs)
hoverController.close()
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
expect(!hoverController.isVisible, "Click/drag cancellation prevents delayed reopening")
if CommandLine.arguments.contains("--preview") {
    let window = NSWindow(contentRect: jobList.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = jobList
    jobList.wantsLayer = true
    jobList.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    window.display()
    if let image = jobList.bitmapImageRepForCachingDisplay(in: jobList.bounds) {
        jobList.cacheDisplay(in: jobList.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/hover-preview.png"))
        print("Rendered synthetic hover preview: build/hover-preview.png")
    }
    window.orderOut(nil)
}
panel.orderOut(nil)
let orcaA = OrcaContext(workspaceID: "repo-a::/projects/alpha", sidebarID: nil, label: "Alpha › main")
let orcaB = OrcaContext(workspaceID: "repo-b::/projects/beta", sidebarID: nil, label: "Beta › main")
let markedA = FollowUp(bundleID: OrcaNavigation.bundleID, appName: "Orca", label: orcaA.label,
                       windowTitle: "Orca", url: nil, selection: nil, orcaContext: orcaA)
let markedB = FollowUp(bundleID: OrcaNavigation.bundleID, appName: "Orca", label: orcaB.label,
                       windowTitle: "Orca", url: nil, selection: nil, orcaContext: orcaB)
expect(!markedA.samePlace(as: markedB), "Two Orca projects remain distinct despite identical window titles")
expect(markedA.samePlace(as: markedA), "Recapturing the same Orca workspace toggles its own job")
var renamedA = markedA
renamedA.orcaContext = OrcaContext(workspaceID: orcaA.workspaceID, sidebarID: "different-sidebar-layout", label: "Renamed Alpha")
expect(markedA.samePlace(as: renamedA), "Orca workspace identity survives label/sidebar changes")
expect(OrcaNavigation.rowWorkspace("worktree-list-option-project%3Aexample%3Alocal%7Crepo-a%3A%3A%2Fprojects%2Falpha") == orcaA.workspaceID,
       "Sidebar row capture uses its exact workspace identifier")
expect(!markedA.samePlace(as: followUp(OrcaNavigation.bundleID, title: "Orca")), "Legacy generic Orca jobs are not guessed or merged")
let markedRoundTrip = try JSONDecoder().decode(FollowUp.self, from: JSONEncoder().encode(markedA))
expect(markedRoundTrip.orcaContext?.workspaceID == orcaA.workspaceID, "Orca target survives JSON persistence")
expect(decoded.orcaContext == nil, "Older follow-up records decode without Orca metadata")
expect(OrcaNavigation.normalizedTabTitle("Working Hermes Close tab ⠼ Hermes") == "Hermes", "Live Orca tab status is normalized")
let catalogs = [OrcaWorkspaceSnapshot(workspaceID: orcaA.workspaceID, titles: ["Hermes"]),
                OrcaWorkspaceSnapshot(workspaceID: orcaB.workspaceID, titles: ["Terminal 1"])]
expect(OrcaNavigation.matchWorkspace(visibleTitles: ["Working Hermes Close tab ⠼ Hermes"], snapshots: catalogs) == orcaA.workspaceID,
       "Orca capture follows the visible UI tab, not caller cwd")
expect(OrcaNavigation.matchWorkspace(visibleTitles: ["Terminal 1"], snapshots: catalogs) == orcaB.workspaceID,
       "Switching visible workspace changes the captured target")
expect(OrcaNavigation.matchWorkspace(visibleTitles: ["Hermes"], snapshots: catalogs + [catalogs[0]]) == nil,
       "Ambiguous Orca captures are rejected rather than opening a wrong project")
if CommandLine.arguments.contains("--orca-live") {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: OrcaNavigation.bundleID).first,
          let window = WindowService.windows(of: AppEntry(running: app)).first,
          let captured = FollowUpCapture.describe(window: window.element, of: app),
          let original = captured.orcaContext else { fatalError("Live Orca workspace capture failed") }
    print("LIVE captured visible Orca context:", original.label)
    if let secondID = ProcessInfo.processInfo.environment["DDD_ORCA_TEST_WORKSPACE"] {
        func roundTrip() {
            defer { _ = OrcaNavigation.activate(original, appURL: app.bundleURL) }
            let second = OrcaContext(workspaceID: secondID, sidebarID: nil, label: "Live test target")
            expect(OrcaNavigation.activate(second, appURL: app.bundleURL), "LIVE request workspace B navigation")
            Thread.sleep(forTimeInterval: 0.7)
            let b = FollowUpCapture.describe(window: window.element, of: app)
            print("LIVE B capture:", b?.orcaContext?.label ?? "nil")
            fflush(stdout)
            expect(b?.orcaContext?.workspaceID == secondID, "LIVE visible Orca UI is workspace B")
            expect(!captured.samePlace(as: b!), "LIVE A and B produce distinct saved jobs")
            FollowUpOpener.open(captured)
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            let restored = FollowUpCapture.describe(window: window.element, of: app)
            expect(restored?.orcaContext?.workspaceID == original.workspaceID, "LIVE DDD opener returns to saved workspace A")
            expect(captured.samePlace(as: restored!), "LIVE recapture of A toggles only A, not B")
            FollowUpOpener.open(b!)
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            let reopenedB = FollowUpCapture.describe(window: window.element, of: app)
            expect(reopenedB?.orcaContext?.workspaceID == secondID, "LIVE DDD opener also returns to saved workspace B")
            print("LIVE round trip passed; user's job file was not accessed")
        }
        roundTrip()
    }
}
print("All core and native UI construction checks passed. No DDD preferences or follow-up store accessed.")
