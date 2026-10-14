# DDD v0.1.0 — experimental first public release

A floating macOS app/window switcher and visual follow-up tracker, built in native Swift.

## Download

- `DDD-0.1.0-macos-universal.zip`: macOS 14+, Apple Silicon and Intel slices.
- `SHA256SUMS.txt`: download beside the ZIP and run `shasum -a 256 -c SHA256SUMS.txt`.

Quit an existing DDD, extract the ZIP, and drag `DDD.app` to Applications.
Grant Accessibility yourself in System Settings. Screen Recording is optional for browser colors.
See the [installation and user guide](https://github.com/dgiulev-blog/DDD/blob/main/docs/USER-GUIDE.md).

## What is included

- Draggable floating D and animated radial app/window picker.
- Numbered, locally stored middle-click follow-ups with visual lines and clickable rings.
- Best-effort return to windows, pages, and selected app contexts.
- Optional browser toolbar color sampling and Tailscale/VNC shortcuts.
- MIT-licensed source, build scripts, contributor docs, privacy documentation, and launch artwork.

## Important before installing

**Ad-hoc signed and NOT notarized.** No valid Apple Developer ID identity was available for this release. Gatekeeper may block the app. Only use Open Anyway in Privacy & Security if macOS offers it and you trust the verified download; otherwise build from source. Do not disable system-wide protections. Checksums and ad-hoc signatures do not authenticate the publisher.

DDD intercepts middle-clicks **system-wide**, including when Show D is off. Quit DDD to restore normal middle-click behavior. Right-clicking an app bubble asks that app to quit; right-clicking a window pill closes its window. Open at Login is attempted on first launch; disable it in the menu if unwanted.

Follow-ups are plaintext local data and may contain sensitive URLs or conversation titles. Navigation and green attention signals are heuristics, not exact session restoration or completion detection. Lists can truncate after two columns. Private Accessibility SPI makes this implementation unsuitable for App Store submission as-is.

## Validation performed

- Compiled both `arm64` and `x86_64` slices targeting macOS 14.0.
- Executed Swift core checks for follow-up identity, JSON round trips, text cleanup, app categories, VNC URLs, and radial layout at center/corners.
- Constructed native D and empty radial UI components on this Apple Silicon Mac and checked their properties without reading/writing the user's follow-up store.
- Checked bundle metadata, ad-hoc signature integrity, archive allowlist, binary equality, SHA-256, documentation links, and a heuristic private-value scan.
- Visually checked the public concept illustration in a browser. It is not an app screenshot.

**Not release-validated:** Intel runtime, macOS 14 hardware/runtime, fresh-user Gatekeeper and permission flows, or the complete end-to-end third-party app compatibility matrix. Do not use DDD as your only record of important work.

[Full documentation](https://github.com/dgiulev-blog/DDD#documentation) · [Source](https://github.com/dgiulev-blog/DDD) · [MIT License](https://github.com/dgiulev-blog/DDD/blob/main/LICENSE)
