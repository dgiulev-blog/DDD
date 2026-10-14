import AppKit

/// A machine on the tailnet that Screen Sharing can connect to.
struct Machine {
    let name: String
    let host: String // Tailscale IP
    let os: String
    let online: Bool

    var vncURL: URL? { URL(string: "vnc://\(host)") }
}

/// Keeps a cached list of Tailscale peers, refreshed in the background.
final class MachineService {
    static let shared = MachineService()
    private(set) var machines: [Machine] = []

    private static let cliPaths = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
                                   "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]

    func start() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard let cli = Self.cliPaths.first(where: FileManager.default.isExecutableFile) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Self.fetch(cli: cli)
            DispatchQueue.main.async { if let list { self.machines = list } }
        }
    }

    private static func fetch(cli: String) -> [Machine]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["status", "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = json["Peer"] as? [String: [String: Any]] else { return nil }
        return peers.values.compactMap { peer -> Machine? in
            let os = peer["OS"] as? String ?? ""
            guard !["iOS", "android", "tvOS"].contains(os),
                  let ip = (peer["TailscaleIPs"] as? [String])?.first(where: { !$0.contains(":") }) else { return nil }
            let dns = (peer["DNSName"] as? String)?.split(separator: ".").first.map(String.init)
            let name = (peer["HostName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? dns ?? ip
            return Machine(name: name, host: ip, os: os, online: peer["Online"] as? Bool ?? false)
        }
        .sorted { ($0.online ? 0 : 1, $0.name.lowercased()) < ($1.online ? 0 : 1, $1.name.lowercased()) }
    }
}
