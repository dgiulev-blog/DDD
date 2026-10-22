# Privacy and local data

This describes the current v0.1.0 Swift implementation, not a promise about every future version or about the applications DDD opens.

## What DDD reads

With Accessibility permission, DDD inspects app/window and Dock accessibility information to list windows, capture follow-ups, match remembered places, and position links. Depending on the app, this can expose window titles, web URLs, selected items, chat names, and visible UI text. Capture walks an app's accessibility tree; it is not limited to the precise element you middle-clicked. A label can fall back to text from an AI-chat heading, including a shortened first prompt.

DDD also uses Accessibility to activate/raise/restore windows, press close buttons, select matching items, and request web accessibility trees in supported browser/Electron apps. Reopening can fall back to a synthetic click on a matched item.

The mouse event tap intercepts middle-button events system-wide while active. It checks the button and uses the click location for capture; it is not a keyboard logger. **Show D off does not disable this event tap. Quit DDD to stop it.**

With optional Screen Recording permission, DDD uses ScreenCaptureKit to capture a narrow top strip of selected browser windows and calculate a dominant color. The current code processes those image pixels in memory; it does not save screenshots to disk or upload them. The macOS permission itself is broader than this implementation's sampling area.

## What DDD saves

| Location | Contents |
| --- | --- |
| `~/Library/Application Support/DDD/followups.json` | Plaintext JSON follow-ups: UUID, app bundle ID/name, label, window title, optional URL/selection, creation timestamp |
| UserDefaults domain `io.prim.ddd` | Preferences and flags such as Show D, D position, login registration attempt, and whether Screen Recording was requested |

Follow-ups are written atomically with Foundation's JSON encoder. **They are not encrypted by DDD.** Anyone or any process able to read that file, your backups, or a synced copy can see it. URLs can contain sensitive identifiers or tokens; labels and selections can reveal private conversations. Filesystem permissions and OS protections are not a substitute for app-level encryption.

Removal updates the active JSON list; there is no secure-erasure guarantee for filesystem history, backups, or copies. Save/load errors are currently ignored and not shown to the user. There is no built-in export UI or cloud sync. See the [user guide](USER-GUIDE.md#backup-and-restore) for manual backup and deletion.

The code logs operational messages such as mouse-monitor startup and app selection with window counts through `NSLog`. These are not a remote analytics system, but local diagnostics may contain app names. Review diagnostics before sharing them.

## Orca context integration

For Orca jobs, DDD additionally saves an optional workspace identifier, sidebar row identifier, and project/workspace label in the same plaintext follow-up file. These identifiers may include filesystem paths or project names. Old records without these fields still load.

To distinguish Orca workspaces, DDD reads visible Accessibility tab headers and a filtered workspace/tab-title catalog through the installed Orca app's own local runtime client. To reopen one, it requests focus of an existing terminal or tab in the saved workspace. This uses Orca's authenticated local transport internally; DDD does not store or print its runtime credentials, pairing codes, or terminal content. It does not query third-party servers itself for this feature, although Orca may contact a remote host while switching a remote workspace.

## Network and other-app boundaries

DDD has **no bundled user data, analytics, or cloud backend**. The inspected Swift source has no DDD HTTP service client or telemetry uploader. This does not mean that using it can never cause network traffic:

- If a supported Tailscale CLI exists locally, DDD runs `tailscale status --json` and holds peer names, addresses, OS values, and online state in memory. Tailscale's own service and networking follow Tailscale's policies, not DDD's.
- Clicking a machine hands a `vnc://` link to the system handler, normally Screen Sharing. That app may make an outgoing connection and request authentication.
- Reopening a page or a supported app deep link delegates to the browser/system application. It may fetch content, contact that app's servers, or expose the URL to its registered handler.
- Opening System Settings or registering the login item delegates to macOS services.

DDD does not supply VNC credentials, host a remote desktop service, or create a cloud account. Tailscale is optional and not bundled.

## Permissions and startup

Accessibility is required for the core workflow. Screen Recording is optional for browser colors. DDD attempts to register **Open at Login** once on first launch; you can disable it from the menu and review macOS Login Items. Hiding the floating UI is not equivalent to quitting or revoking permissions.

## Practical precautions

- Try the app with non-sensitive test content before marking real work.
- Treat follow-up files, backups, screenshots, and diagnostic attachments as private. Redact URLs, titles, chat selections, peer names, and addresses before reporting bugs.
- Keep a separate record of essential tasks; DDD's capture, reopen, and persistence are experimental.
- Download from the repository's release page and verify the checksum, understanding that a checksum does not authenticate the publisher. Ad-hoc signing is not a valid Developer ID signature; releases are not notarized.
- Review granted macOS permissions and disable Open at Login if you do not want background use.

For security concerns, see [SECURITY.md](../SECURITY.md).
