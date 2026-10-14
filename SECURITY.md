# Security

DDD v0.1.0 is experimental. No security audit, response-time guarantee, or long-term supported-version policy is claimed. Check the latest release notes before use; report the exact version/commit affected.

## Reporting a concern

**Do not publish private follow-up data or exploit details in a public issue.** If the repository offers GitHub's **Report a vulnerability** private-reporting option, use it. If that option is absent, open a minimal issue asking the maintainer for a private reporting channel without disclosing the exploit, private data, or reproduction details that would expose users. No separate security email or private channel is promised here.

Once a private channel is established, include the affected version/commit, macOS version, architecture, relevant permissions, impact, and minimal reproduction using synthetic/non-sensitive data. Redact credentials, tokens, URLs, titles, chat selections, and Tailscale peer information. Never attach a live `followups.json` or private personal/corporate documents.

## Trust boundaries

- **Accessibility:** DDD can inspect UI text and control windows/items in other apps. Capture is not restricted to the element directly under the mouse; reopening may use synthetic clicks. Grant permission only to a trusted build.
- **Global mouse input:** the middle-button event monitor swallows middle-clicks system-wide while active, even with Show D off. Quit DDD to stop it.
- **Local data:** `~/Library/Application Support/DDD/followups.json` is plaintext and can contain sensitive titles, URLs, or selections. Preferences use UserDefaults domain `io.prim.ddd`. DDD does not encrypt its storage or securely erase backup copies.
- **Screen Recording:** optional browser-color sampling processes a narrow strip in memory; the OS permission grants broader capture capability.
- **External handlers:** page URLs, app deep links, and `vnc://` links go to system apps/registered handlers. Those apps may access the network or request authentication. A modified follow-up file could affect what DDD opens; do not import untrusted files.
- **Local Tailscale CLI:** when found in a supported path, DDD executes `tailscale status --json`. It relies on the installed executable and Tailscale service; it does not implement their security controls.
- **Private SPI:** `_AXUIElementGetWindow` is not a stable public contract. The current app is not App Store-ready.

There is no bundled user data, analytics, or cloud backend in DDD. This does not establish a security guarantee for the OS, local files, or applications it launches.

## Release verification and Gatekeeper

Release signing is **ad hoc**, without a valid Developer ID signature, and releases are **not notarized**. Verify downloaded ZIPs against the published `SHA256SUMS.txt` as described in the [user guide](docs/USER-GUIDE.md#verify-a-download). Checksums detect disagreement with that file; they do not authenticate the publisher and cannot protect against an attacker who can replace both files.

Gatekeeper may block a downloaded app. For a trusted, verified download, use **System Settings → Privacy & Security → Open Anyway** only if offered. Otherwise build from source. Do not globally disable Gatekeeper, strip quarantine as a blanket workaround, or weaken system protections to run DDD.

For backup/deletion and startup settings, see the [user guide](docs/USER-GUIDE.md) and [Privacy](docs/PRIVACY.md).
