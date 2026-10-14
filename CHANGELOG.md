# Changelog

This records the initial public version's implemented behavior and limitations. Release dates and asset availability are defined by [GitHub Releases](https://github.com/dgiulev-blog/DDD/releases), not implied by this entry.

## v0.1.0 — Experimental initial public version

### Features

- Native Swift/AppKit accessory app with a menu bar item and draggable floating D.
- Animated radial app picker and window/follow-up pills; app grouping and minimized-window restoration attempts.
- System-wide middle-click follow-up toggle using Accessibility context: titles, URLs, or selected-item text where exposed.
- Local JSON persistence, creation-order numbering, and follow-up count badges.
- Click-through visual lines to window/Dock targets, clickable endpoint rings, hover details, and right-click follow-up removal.
- App-level Dock badge/dialog/sheet heuristics for green links and pulsing endpoints.
- Best-effort reopening via browser title matching, saved URLs, selected UI items, and recognized app deep links.
- Optional browser-strip color sampling with Screen Recording permission.
- Optional local Tailscale CLI peer listing and system-handler VNC link opening.
- Single-instance guard, Show D setting, display-change handling, and first-launch Open at Login registration attempt.
- Public English documentation under the MIT License; copyright Dimitar Giulev.

### Distribution and known limitations

- macOS 14+ target; universal arm64 + x86_64 distribution. Automated core and native UI-construction checks ran on Apple Silicon; Intel runtime behavior and end-to-end permission flows are not release-validated.
- Build-only `./build.sh`, universal `ARCHS='arm64 x86_64' ./build.sh`, and `./scripts/package.sh` workflow for `dist/DDD-0.1.0-macos-universal.zip` plus `dist/SHA256SUMS.txt`.
- Ad-hoc signing only: no valid Developer ID signature and no notarization; Gatekeeper may block downloads.
- Accessibility required; Screen Recording optional. Open at Login is attempted on first launch and can be disabled in the menu.
- Middle-click intercepted system-wide while the monitor is active, **including with Show D off**. Quit DDD to restore native behavior.
- Right-clicking an app bubble requests that app quit; a window pill closes its window; a follow-up pill removes the reminder.
- Reopening and attention signals are heuristic, not exact session restoration or semantic completion detection.
- No global keyboard shortcut; Escape dismisses the picker. Choice lists truncate after two columns.
- Plaintext follow-ups can contain sensitive URLs/titles/chat selections. Persistence errors are silent; important work needs a separate record/backup.
- Private `_AXUIElementGetWindow` SPI; current implementation is not App Store-ready.
- No bundled user data, analytics, or cloud backend. Other apps launched through URLs/VNC may use the network.
