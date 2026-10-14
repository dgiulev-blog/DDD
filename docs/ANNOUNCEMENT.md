# Repository announcement: DDD v0.1.0

## A visible way back to unfinished work on your Mac

DDD is an experimental, MIT-licensed macOS utility built around a floating **D**. Click it to fan out app bubbles and choose a window. Middle-click inside an app to save a local follow-up, then use a numbered item or a clickable line endpoint to try returning to that place later.

The idea is simple: keep reminders attached to the desktop where the work happens, rather than in another list you have to remember to open.

### In this first version

- A draggable D and radial app/window picker, including minimized-window restoration attempts.
- Local follow-ups captured from accessibility information such as window titles, page URLs, and selected items.
- Visible counts and links toward a window or Dock item, with clickable endpoint rings.
- Green links and pulsing rings when an app has a Dock badge or dialog/sheet. These are **attention heuristics**, not completion detection.
- Optional browser-toolbar color sampling with Screen Recording permission.
- Optional local Tailscale peer listing that hands VNC links to Screen Sharing/the system handler.

### Try it with clear expectations

DDD v0.1.0 requires **macOS 14+**. A universal arm64 + x86_64 experimental download is available at [GitHub Releases](https://github.com/dgiulev-blog/DDD/releases/tag/v0.1.0). Automated core and native UI-construction checks ran on Apple Silicon; Intel runtime behavior and end-to-end permission flows are not release-validated. You can also build from source with `./build.sh`.

This release is **ad-hoc signed, not Developer ID signed, and not notarized**. Gatekeeper may block it. Follow the [install and verification guide](USER-GUIDE.md#install-or-update); use Open Anyway only for a trusted, verified download if macOS offers it, or build from source. Do not disable system security protections.

Accessibility is required for the core workflow. Screen Recording is optional for colors. On first launch DDD attempts to enable **Open at Login**; turn it off from the menu if unwanted.

**Read this before using a middle-button mouse:** DDD intercepts middle-clicks **system-wide**, even with Show D off. Quit DDD to restore their normal behavior. Right-clicking an app bubble requests that app quit; right-clicking a window pill closes it, while right-clicking a follow-up removes only the reminder.

Follow-ups are plaintext local data and can contain sensitive URLs, titles, or chat selections. DDD has no bundled user data, analytics, or cloud backend, but opening pages/deep links or VNC connections delegates to apps that may use the network. Read [Privacy](PRIVACY.md).

Reopening is best effort, not exact session restoration. Lists can truncate after two columns; Escape dismisses the picker, but there is no global shortcut. Private accessibility SPI makes the current implementation not App Store-ready.

### Feedback that helps

Try a harmless page or test document first. Report reproducible capture, matching, layout, or window-focus problems with the macOS version, architecture, app version, and redacted steps. Intel testing and keyboard-accessibility feedback would be useful; do not share real follow-up files, private conversation titles, or tailnet details publicly.

Start with the [README](../README.md), [user guide](USER-GUIDE.md), and [contribution guide](../CONTRIBUTING.md). Copyright Dimitar Giulev; see the [MIT License](../LICENSE).
