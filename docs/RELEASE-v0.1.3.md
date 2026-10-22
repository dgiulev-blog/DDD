# DDD v0.1.3 — Return to a specific Orca project/workspace

Middle-click inside an Orca workspace to remember that workspace, not just “Orca.”
The job box displays the project/workspace name. Click it to navigate back there.
You can also mark a specific workspace row in Orca's sidebar.

- Two workspaces in one Orca window remain separate jobs.
- Middle-clicking the same workspace toggles only that workspace's reminder.
- Existing generic Orca jobs remain intact, but must be removed and re-marked to gain project context.
- Background capture and bounded local-runtime requests avoid blocking the DDD UI.

Validated with actual capture → switch → DDD reopening → UI readback, across two local
workspaces and a remote terminal-backed project in Orca 1.4.237. JSON compatibility,
identity, title normalization, ambiguity handling, and existing regression checks pass.

Limitations: the integration uses Orca's installed internal runtime client. Duplicate
visible tab titles can make capture ambiguous; use the specific sidebar workspace row.
Reopening needs an existing published workspace tab. Closed/disconnected/empty workspaces,
other Orca versions, and all non-terminal surfaces are not fully validated. No terminal input,
agent launches, or intentional terminal creation is used for navigation.

Download `DDD-0.1.3-macos-universal.zip` with `SHA256SUMS.txt`; verify using
`shasum -a 256 -c SHA256SUMS.txt`. Quit the old DDD and move the extracted app into Applications.
Requires macOS 14+, includes Apple Silicon and Intel slices. Intel runtime is not validated.

**Experimental, ad-hoc signed and unnotarized.** Gatekeeper may block it. Do not disable
system-wide protections. Existing global middle-click interception and local plaintext
storage caveats still apply. Orca workspace identifiers may include private filesystem paths.
