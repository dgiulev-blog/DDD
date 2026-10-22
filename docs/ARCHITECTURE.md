# Architecture

DDD v0.1.1 is a native Swift/AppKit accessory application. `Sources/main.swift` creates `NSApplication`, installs `AppDelegate`, selects `.accessory` activation policy, and runs the application loop. It is not a browser extension or a hosted service.

## Source map

| File | Responsibility |
| --- | --- |
| `main.swift` | AppKit entry point |
| `AppDelegate.swift` | Single-instance guard, menu bar, preferences, login item, permission prompts, picker lifecycle, capture wiring |
| `DPanel.swift` | Draggable floating D, count badge, saved position callback, pointer tracking |
| `JobsHover.swift` | Delayed non-activating hover panel with all numbered jobs in a scroll view; click-to-reopen |
| `RadialView.swift` | Animated app bubbles, window/follow-up/machine pills, actions and layout |
| `WindowService.swift` | App grouping, AX window enumeration, focus/restore/close, window IDs |
| `MiddleClick.swift` | System-wide middle-button event tap and capture-result toast |
| `FollowUps.swift` | Codable follow-up model, local store, AX capture/walk helpers, best-effort reopening |
| `LinksOverlay.swift` | Per-screen click-through line panels, clickable endpoint rings, Dock/window targeting and attention heuristic |
| `BrowserTheme.swift` | Optional ScreenCaptureKit browser-strip color sampling |
| `MachineService.swift` | Local Tailscale CLI discovery, JSON parsing and peer cache |

## Startup and settings

Startup rejects a second process with the same bundle identifier. It attempts `SMAppService.mainApp.register()` once, records the attempt in UserDefaults, creates the status item and floating panel, subscribes to workspace/display/store notifications, starts peer refresh, prompts for Accessibility if needed, and retries event-tap startup every three seconds until it succeeds.

The `isOn` preference defaults to true. Turning Show D off hides the UI and stops link refresh; it **does not stop the middle-click monitor or Tailscale refresh**. Preferences live in the `io.prim.ddd` UserDefaults domain. The D's position is retained and checked for intersection with a connected screen on launch/display changes.

## Picker and window operations

`WindowService.runningApps()` primarily includes regular running apps with AX windows, plus apps with saved follow-ups. Installed apps with follow-ups can appear even when closed. Without AX trust, it keeps regular apps instead of filtering them all away. Screen Sharing is placed first when installed; other apps are grouped by browser identifiers, communication identifiers, or bundle app-category metadata, then launch time.

The radial view lays out bubbles on staggered rings/arcs within the visible screen. Selecting an app builds choices in order: saved follow-ups, AX windows, then Tailscale machines for Screen Sharing. A sole window is focused directly. Choices are restricted to two columns; later choices are cut off, not paginated. Escape or an empty-space click dismisses the picker. No global shortcut or full keyboard navigation is implemented.

Window operations use AX attributes/actions and `NSRunningApplication`: unhide/activate, unminimize, set main/frontmost, raise, and retry raising after activation. Window close presses its close button. Right-clicking a bubble calls `terminate()` on the other app, not a force kill; the app can refuse or prompt to save.

## Capture → store → reopen

1. `MiddleClickMonitor` installs a session-level CG event tap for other-mouse down/up. Button number 2 is swallowed; down schedules capture on the main queue. Other buttons pass through. Disabled taps are re-enabled.
2. `FollowUpCapture` hit-tests the system AX tree, excludes DDD itself, finds the owning app/window, and scans for context. It requests web AX trees for known browsers/Electron apps.
3. Capture uses the window document URL or a web-area URL, titles, deepest selected-item text, and fallback labels. Slack has a message-list channel-ID heuristic; some AI chats have a first-heading fallback. Traversal is bounded by node/depth limits.
4. `FollowUpStore.toggle` deduplicates by bundle ID + URL when both records have URLs, otherwise by bundle ID + window title + selection. Repeating a capture removes the matching record.
5. The store encodes the array atomically to `~/Library/Application Support/DDD/followups.json` and posts a change notification. Display numbers are current array positions, not stable IDs. Load/save errors are silent.
6. `FollowUpOpener` uses app-specific deep links when recognized, browser title-prefix AX tab matching or URL opening, exact window-title matching with first-window fallback, and selected-item text-prefix matching. Reselection tries AX press/selection, then a synthetic center click with pointer restoration.

This is heuristic navigation, **not exact session restoration**. It does not preserve a complete UI state, scroll/caret positions, or guarantee that a title/text match represents the original item.

## Persistent visual links

Link refresh runs about every 0.5 seconds, with AX/Dock discovery on a serial background queue and panel updates on the main queue. One transparent, click-through line panel is created per screen. Separate small endpoint panels handle clicks, right-click removal, hover details, and green-state pulsing.

Targets prefer a title-matched window, otherwise the first window, then a minimized Dock thumbnail or app Dock icon. Multiple endpoints targeting one spot are offset horizontally. No target means no visible endpoint, not deletion of the follow-up. When the picker is open, links start at corresponding app bubbles instead of the D.

Green state is inferred at the **app level** from Dock badge text or dialog/sheet presence. It is not semantic task completion, message readiness, or a reliable indication for a specific follow-up.

## Optional integrations

**Browser colors:** a fixed browser-ID set identifies Chrome, Comet, Firefox, Safari, Arc, Edge, Brave, and Vivaldi. This is detection logic, not a tested compatibility matrix. With Screen Recording permission, ScreenCaptureKit captures a 12-pixel-high top strip and buckets RGB colors to find a dominant color. Images are processed in memory, not persisted. Failed sampling leaves default colors.

**Tailscale:** `MachineService` discovers an executable in three fixed local paths and launches `status --json`. It caches peers with IPv4 addresses, excluding iOS/Android/tvOS, sorted online-first and by name. Refresh runs every 30 seconds and on picker opening; failures can leave a stale cache. Picking a machine sends `vnc://<address>` through `NSWorkspace`, delegating transport/authentication to the handler. DDD neither installs Tailscale nor implements a VNC client.

## Distribution and constraints

- Target: macOS 14+. Build: `./build.sh`; universal: `ARCHS='arm64 x86_64' ./build.sh`; packaging: `./scripts/package.sh`.
- Universal archive: `dist/DDD-0.1.1-macos-universal.zip`, accompanied by `dist/SHA256SUMS.txt`. Automated core and native UI-construction checks ran on Apple Silicon. Intel runtime behavior and end-to-end permission flows are not release-validated.
- Releases are ad-hoc signed, without a valid Developer ID signature, and not notarized.
- `WindowEntry.windowID` binds private **`_AXUIElementGetWindow` SPI** via `@_silgen_name`. This is not a public API contract; OS updates may break it. The current app is not App Store-ready.
- Accessibility trees, Dock structures, titles, deep links, and external apps can change. Bounds/timeouts reduce some AX work but do not guarantee responsiveness or correct matching.
- Plaintext storage has no migration/error-recovery UI or built-in encryption. There is no bundled user data, analytics, or cloud backend.

See [Privacy](PRIVACY.md) for data boundaries and [Contributing](../CONTRIBUTING.md) for review/testing expectations.
