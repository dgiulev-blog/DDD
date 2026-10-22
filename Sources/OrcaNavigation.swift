import AppKit
import ApplicationServices

/// Local navigation metadata only. No terminal content, runtime token, or pairing code is stored.
struct OrcaContext: Codable {
    let workspaceID: String
    let sidebarID: String?
    let label: String
}

struct OrcaWorkspaceSnapshot: Decodable {
    let workspaceID: String
    let titles: [String]
}

enum OrcaNavigation {
    static let bundleID = "com.stablyai.orca"

    static func normalizedTabTitle(_ raw: String) -> String {
        var text = raw.components(separatedBy: " Close tab").first ?? raw
        for prefix in ["Working ", "Waiting ", "Idle ", "Done ", "Error ", "Needs input "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        return String(text.unicodeScalars.filter { !(0x2800...0x28FF).contains($0.value) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchWorkspace(visibleTitles: [String], snapshots: [OrcaWorkspaceSnapshot]) -> String? {
        let wanted = Set(visibleTitles.map(normalizedTabTitle).filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return nil }
        let scores = snapshots.map { wanted.intersection(Set($0.titles.map(normalizedTabTitle))).count }
        guard let best = scores.max(), best > 0 else { return nil }
        let matches = snapshots.indices.filter { scores[$0] == best }
        // Extra UI tabs may not have published yet. Require a unique strongest match.
        return matches.count == 1 ? snapshots[matches[0]].workspaceID : nil
    }

    static func context(window: AXUIElement, app: NSRunningApplication, hit: AXUIElement? = nil) -> OrcaContext? {
        var explicitRow: String?
        var parent = hit
        for _ in 0..<20 {
            guard let element = parent else { break }
            if let id = WindowService.attribute(element, "AXDOMIdentifier") as? String,
               rowWorkspace(id) != nil { explicitRow = id; break }
            parent = axElement(WindowService.attribute(element, kAXParentAttribute))
        }
        var visibleTitles: [String] = []
        var rows: [String: String] = [:]
        var projectLabels: [String: String] = [:]
        walk(window, maxNodes: 8000) { element, _ in
            let title = WindowService.attribute(element, kAXTitleAttribute) as? String ?? ""
            let roleDescription = WindowService.attribute(element, kAXRoleDescriptionAttribute) as? String ?? ""
            if roleDescription == "sortable", title.contains(" Close tab") { visibleTitles.append(title) }
            if let id = WindowService.attribute(element, "AXDOMIdentifier") as? String,
               id.hasPrefix("worktree-list-option-"), let key = decodedRow(id) {
                if let workspace = rowWorkspace(id) { rows[workspace] = id }
                else if let split = title.range(of: " Project actions for ") {
                    projectLabels[key] = String(title[..<split.lowerBound])
                }
            }
            return true
        }
        let workspaceID: String
        if let row = explicitRow, let id = rowWorkspace(row) {
            workspaceID = id
        } else {
            guard let data = runBridge(appURL: app.bundleURL, action: "list"),
                  let catalog = try? JSONDecoder().decode([OrcaWorkspaceSnapshot].self, from: data),
                  let id = matchWorkspace(visibleTitles: visibleTitles, snapshots: catalog) else { return nil }
            workspaceID = id
        }
        let sidebarID = explicitRow ?? rows[workspaceID]
        let key = sidebarID.flatMap(decodedRow)?.components(separatedBy: "|").first
        let project = key.flatMap { rowKey in
            projectLabels.keys.sorted { $0.count > $1.count }
                .first(where: { rowKey == $0 || rowKey.hasPrefix($0 + ":") }).flatMap { projectLabels[$0] }
        }
        let folder = workspaceID.components(separatedBy: "::").last.map { ($0 as NSString).lastPathComponent } ?? "Workspace"
        let label = project.map { "\($0) › \(folder)" } ?? folder
        return OrcaContext(workspaceID: workspaceID, sidebarID: sidebarID, label: label)
    }

    static func decodedRow(_ id: String) -> String? {
        let prefix = "worktree-list-option-"
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count)).removingPercentEncoding
    }

    static func rowWorkspace(_ id: String) -> String? {
        guard let key = decodedRow(id), let separator = key.lastIndex(of: "|") else { return nil }
        let workspace = String(key[key.index(after: separator)...])
        return workspace.contains("::/") ? workspace : nil
    }

    /// Synchronous worker-thread primitive, also exercised by the opt-in live round-trip test.
    static func activate(_ context: OrcaContext, appURL: URL?) -> Bool {
        guard let data = runBridge(appURL: appURL, action: "open", workspaceID: context.workspaceID),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return result["activated"] as? Bool == true && result["worktreeId"] as? String == context.workspaceID
    }

    static func open(_ context: OrcaContext) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let finish: () -> Void = {
            DispatchQueue.global(qos: .userInitiated).async {
                let success = activate(context, appURL: appURL)
                DispatchQueue.main.async {
                    if success {
                        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                    } else {
                        Toast.show("Can't reopen Orca workspace — re-mark it in Orca", near: CGEvent(source: nil)?.location ?? .zero)
                    }
                }
            }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard error == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: finish)
            }
        } else { finish() }
    }

    private static func runBridge(appURL: URL?, action: String, workspaceID: String = "") -> Data? {
        guard let appURL,
              let executable = Bundle(url: appURL)?.executableURL else { return nil }
        let resources = appURL.appendingPathComponent("Contents/Resources")
        let module = resources.appendingPathComponent("app.asar.unpacked/out/cli/runtime-client.js")
        guard FileManager.default.fileExists(atPath: module.path) else { return nil }
        // Reuse the installed app's own authenticated local transport. No auth material crosses stdout.
        let script = #"""
        const {RuntimeClient}=require(process.argv[1]);
        (async()=>{
          const client=new RuntimeClient(undefined,2500,null,null);
          if(process.argv[2]==='list') {
            const r=await client.call('session.tabs.listAll');
            console.log(JSON.stringify(r.result.snapshots.map(s=>({workspaceID:s.worktree,titles:s.tabs.map(t=>t.customTitle||t.title||'')}))));
          } else if(process.argv[2]==='open') {
            const all=await client.call('session.tabs.listAll');
            const snapshot=all.result.snapshots.find(s=>s.worktree===process.argv[3]);
            if(!snapshot || !snapshot.tabs.length) throw new Error('workspace_unavailable');
            const tab=snapshot.tabs.find(t=>t.isActive) || snapshot.tabs[0];
            if(tab.type==='terminal' && tab.terminal) {
              const r=await client.call('terminal.focus',{terminal:tab.terminal,navigation:'host'});
              console.log(JSON.stringify({activated:r.result.focus.navigated===true,worktreeId:r.result.focus.worktreeId}));
            } else {
              await client.call('session.tabs.activate',{worktree:'id:'+process.argv[3],tabId:tab.parentTabId||tab.id,
                ...(tab.leafId?{leafId:tab.leafId}:{}),navigation:'host',intent:'automatic'});
              console.log(JSON.stringify({activated:true,worktreeId:process.argv[3]}));
            }
          } else {process.exitCode=1;}
        })().catch(()=>{process.exitCode=1;});
        """#
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-e", script, module.path, action, workspaceID]
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ORCA_") }
        env["ELECTRON_RUN_AS_NODE"] = "1"
        env.removeValue(forKey: "NODE_OPTIONS")
        process.environment = env
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return process.terminationStatus == 0 && data.count < 1_048_576 ? data : nil
    }
}
