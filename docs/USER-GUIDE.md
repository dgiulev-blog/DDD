# DDD user guide

DDD v0.1.0 is experimental. It requires macOS 14 or later. A universal arm64 + x86_64 download is provided. Automated core and native UI-construction checks ran on Apple Silicon; Intel runtime behavior and end-to-end permission flows are not release-validated.

## Install or update

1. Get an available ZIP and `SHA256SUMS.txt` from [GitHub Releases](https://github.com/dgiulev-blog/DDD/releases). Choose the v0.1.0 experimental release and read its notes before installing.
2. Verify the ZIP before opening it (below).
3. If updating, right-click DDD's **menu bar icon** and select **Quit DDD**. Do not replace a running copy.
4. Expand the ZIP in Finder. Drag `DDD.app` into **Applications**, replacing the old copy if appropriate.
5. Open `DDD.app` from Applications.

The release is ad-hoc signed, has no valid Developer ID signature, and is not notarized. Gatekeeper may block it. If you trust the source and have verified the download, macOS may offer **Open Anyway** under **System Settings → Privacy & Security** after a blocked launch. Use that option only if offered and only for a download you trust. If it is not offered, build from source instead. Do not disable Gatekeeper or strip quarantine as a blanket workaround.

### Verify a download

Put the ZIP and checksum file in the same folder. Open Terminal in that folder and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The ZIP's entry should report `OK`. A mismatch, missing file, or verification error is a reason to stop and redownload or investigate—not to ignore the check. A checksum confirms agreement with the published checksum file; it is not a Developer ID signature or proof that the publisher is trustworthy.

### Build instead

From a checkout on a Mac with Apple's command-line developer tools and a suitable macOS SDK:

```sh
./build.sh
```

This builds only; it does not launch DDD. For a universal binary and the release archive:

```sh
ARCHS='arm64 x86_64' ./build.sh
./scripts/package.sh
```

Packaging produces `dist/DDD-0.1.0-macos-universal.zip` and `dist/SHA256SUMS.txt`. Install the packaged app manually as above.

## First-launch permissions and settings

- **Accessibility is required** for window inspection/control, follow-up capture, and the middle-click event monitor. Allow DDD under **System Settings → Privacy & Security → Accessibility**. The menu may offer **Grant Accessibility Permission…** while permission is missing.
- **Screen Recording is optional.** DDD can request it when displaying browser window pills. It samples a narrow top strip of browser windows to choose pill colors. You can decline and keep the default colors.
- **Open at Login is attempted automatically on first launch.** Right-click the menu bar icon and turn off **Open at Login** if you do not want it. Check macOS Login Items settings if registration needs approval or does not take effect.

Accessibility is powerful permission: DDD can read UI text and press UI elements. Only grant it to a copy you trust. Screen Recording is a broader system permission than the small strip DDD currently samples.

## A first five-minute walkthrough

Use a non-sensitive browser page or test document to learn the controls.

1. Open a browser and another app, such as TextEdit. Place a harmless test document in TextEdit.
2. Find the floating **D**, initially near the upper-right of the main screen. Drag it to a comfortable location; DDD remembers its position.
3. Click the D. App bubbles fan out. Click TextEdit's bubble. If it has one window and no other choices, DDD goes straight to it; otherwise click the desired window pill.
4. With a mouse that sends a genuine middle-button event, middle-click inside the test document's window. A toast confirms the captured label and number. DDD remembers the app/window context, **not the exact clicked text or caret position**.
5. Click the D and choose TextEdit again. A numbered follow-up pill appears before its window pills. Click the follow-up to try returning to that place. You can also click its endpoint ring when the line has a visible window or Dock target.
6. Hover over an endpoint ring to see its app, label, and time marked. Remove the test follow-up by right-clicking that ring or its numbered pill. Middle-clicking the same captured place again also toggles it off.
7. Right-click DDD's menu bar icon to inspect **Show D**, **Open at Login**, and **Quit DDD**.

A trackpad or mouse without a middle-button event can use the picker but has no built-in substitute for creating follow-ups. There is no global keyboard shortcut for opening DDD or marking a follow-up.

## Control reference

| Control | Effect |
| --- | --- |
| Drag the floating D | Move it; closes an open picker |
| Click the floating D | Open or close the picker |
| Click an app bubble | Show follow-ups/windows or activate the sole window directly |
| Click a window pill | Focus and attempt to restore that window if minimized |
| Click a numbered follow-up pill or endpoint ring | Attempt to reopen the remembered place |
| Middle-click in another app | Add/remove a follow-up for its captured context |
| Right-click an app bubble | Request that **the other app quit**, affecting all its windows |
| Right-click a window pill | Press that window's close button; the other app may ask to save |
| Right-click a follow-up pill or endpoint ring | Remove the saved follow-up, not the document or chat |
| Escape or click empty picker space | Dismiss the picker |
| Left-click DDD's menu bar icon | Toggle Show D |
| Right-click or Control-click DDD's menu bar icon | Open DDD's settings/quit menu |

**Show D is not a pause switch.** It hides the D/picker/link display but does not stop capture. While the monitor is active, middle-button down/up events are swallowed **system-wide** instead of reaching the app under the pointer. Use **Quit DDD** to restore normal middle-click behavior, including opening browser links in new tabs.

## What follow-ups mean

Follow-ups retain creation order. Their displayed numbers are positions, not stable IDs; removing one renumbers later items. The D and menu bar show a total. App bubbles show a few follow-up numbers or a count when there are more.

DDD reads accessibility information to capture a URL, window title, label, or selected item when an app exposes it. Browser tabs are matched by title prefixes; if a match is missing, opening the saved URL can create a new tab. Selected native-app items are matched by text. Some supported app URLs can become deep links, including Slack, Claude, and Notion; some Messages titles can become `imessage://` links. These are implementation heuristics, not a compatibility guarantee.

There is no exact session snapshot, reliable scroll-position restore, or automatic completion tracking. Changed titles, duplicate names, unavailable accessibility trees, signed-out apps, and changed URL handlers can return to the wrong place or fail. DDD may activate an app or its first available window as a fallback.

### Lines and colors

Lines point to a title-matched window, a fallback window, a minimized Dock thumbnail, or an app's Dock icon. If none is available, the follow-up can remain saved without a visible line. Lines are click-through; their endpoint rings are clickable.

Purple is the normal link color. Green links and pulsing rings mean DDD found a Dock badge or sheet/dialog for the **app**. A badge could just be an unread count unrelated to your saved place. Even if a tooltip says “waiting for your input,” this is a heuristic—not proof that a task finished or needs a response.

## Optional Screen Sharing and Tailscale

Screen Sharing is placed first when available, including when it is not running. DDD checks for a local Tailscale executable at `/usr/local/bin/tailscale`, `/opt/homebrew/bin/tailscale`, or inside `/Applications/Tailscale.app`, then runs `tailscale status --json`. Peer information refreshes approximately every 30 seconds and when opening the picker.

Peers with an IPv4 address are listed, excluding iOS, Android, and tvOS entries. Click a peer to pass a `vnc://` URL to the system handler. This does **not** install Tailscale, enable remote Screen Sharing, authenticate you, or guarantee connectivity. The target must offer VNC/Screen Sharing and your tailnet/network permissions must allow it. Offline peers may still be listed. Without a supported CLI, normal DDD features still work.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No floating D | Left-click the menu bar icon or enable Show D. If needed, quit and relaunch from Applications. |
| Apps appear but windows/capture do not work | Confirm Accessibility permission for the current DDD copy. Quit and relaunch after changing permissions. |
| Permission stopped working after replacement/rebuild | macOS may treat a changed ad-hoc build differently. Review the DDD entry in Accessibility and grant permission to the installed copy again if necessary. |
| Browser colors are absent | Default colors are expected without Screen Recording; inspect that permission and restart if macOS asks. Colors are optional. |
| Middle-click stopped doing its usual action | Expected while DDD's event monitor is active—even with Show D off. Quit DDD. |
| “Can't remember this spot” | Capture could not find a usable foreign app/window through Accessibility. Try inside a standard window and check permission. |
| Follow-up opens a wrong/duplicate page or chat | Title-prefix and UI-text matching are best effort. Open it manually, remove the stale follow-up, and mark the current context again. |
| Some windows or follow-ups are missing from the picker | Lists are limited to **two columns**, with later entries truncated; there is no scrolling overflow list. Use the app's own window controls and reduce stale follow-ups. |
| Saved follow-ups disappeared after restart | Check the local file/backup. Loading and saving errors are currently silent; do not rely on DDD as the only record of important work. |
| Tailscale peers are missing or connection fails | Confirm the CLI location, login/status, target Screen Sharing service, network access, and system VNC handler. DDD cannot configure them. |
| Keyboard alone cannot open the picker | No global shortcut or full keyboard-navigation workflow is implemented. Escape only dismisses an already-open picker. |

## Backup and restore

Follow-ups are plaintext at:

```text
~/Library/Application Support/DDD/followups.json
```

They may include private URLs, titles, selected chat names, and labels. **Quit DDD before backing up or restoring** so the in-memory list cannot overwrite restored data. In Finder, use **Go → Go to Folder…** to open `~/Library/Application Support/DDD/`, then copy `followups.json` to a private backup. Restore it to the same location while DDD is closed, then relaunch. Do not upload it to a public issue or repository.

Preferences use UserDefaults domain `io.prim.ddd` (visibility, D position, and one-time permission/login flags). To export them separately:

```sh
defaults export io.prim.ddd "$HOME/Desktop/DDD-preferences.plist"
```

Keep that file private too. Restore while DDD is quit with `defaults import io.prim.ddd /path/to/DDD-preferences.plist`. App preferences do not replace macOS permission decisions or login-item registration; review those separately after moving machines.

## Uninstall

1. Disable **Open at Login** in DDD's menu; review macOS Login Items if it remains listed.
2. Choose **Quit DDD** from the menu bar icon. This also ends middle-click interception.
3. Move `/Applications/DDD.app` to the Trash.
4. Keep your backup if wanted. To delete saved follow-ups, move `~/Library/Application Support/DDD/` to the Trash.
5. Optionally remove preferences with `defaults delete io.prim.ddd` in Terminal. This deletes DDD's preference domain, not the follow-up file.
6. Review DDD's entries in Accessibility and Screen Recording settings and remove/revoke them as macOS permits.

Deleting the app alone does not delete saved follow-ups, backups, or preference data.
