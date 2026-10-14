# Contributing to DDD

DDD v0.1.0 is experimental, MIT-licensed open-source software. Copyright Dimitar Giulev. See [LICENSE](LICENSE) for terms. Small, focused bug reports and changes are welcome; do not assume a proposed feature or pull request will be accepted.

## Report a bug

Use [repository issues](https://github.com/dgiulev-blog/DDD/issues) for non-sensitive reproducible problems. Include:

- DDD version or commit, macOS version, and Apple Silicon/Intel architecture.
- Downloaded versus locally built copy and current Accessibility/Screen Recording permissions.
- Relevant other-app name/version and mouse device/button mapping.
- Minimal steps, expected result, and actual result, preferably with a harmless test document/page.
- Whether Show D is enabled and whether quit/relaunch changes the result.

Redact screenshots, logs, URLs, chat labels, file paths, peer names/addresses, and any identifiers that could disclose private data. **Do not attach your real `followups.json`.** Use synthetic fixtures you created for the report, clearly labeled as such. See [SECURITY.md](SECURITY.md) for security reports.

## Development

Read [Architecture](docs/ARCHITECTURE.md) and [Privacy](docs/PRIVACY.md) before changing capture, reopening, or persistence. Work on a Mac with Apple's command-line developer tools and an SDK supporting the macOS APIs used by the source.

```sh
./build.sh                         # build only
ARCHS='arm64 x86_64' ./build.sh     # universal build
./scripts/package.sh              # dist ZIP and SHA256SUMS.txt
```

Packaging targets `dist/DDD-0.1.0-macos-universal.zip` and `dist/SHA256SUMS.txt`. Quit an existing DDD before replacing or running a different build. macOS may require Accessibility permission to be reviewed for changed ad-hoc builds. Do not automate away permission prompts or disable Gatekeeper.

## Change expectations

- Keep the change focused and describe why it is needed.
- Preserve the single-instance behavior and explicitly document changes to global input interception, startup, or permissions.
- Bound AX traversal and consider main-thread responsiveness and stale app/window references.
- Do not turn title/selection matching or Dock badges into claims of exact restoration or semantic completion.
- Treat saved URLs, labels, selections, and screenshots as sensitive. Never commit personal documents, live follow-up files, credentials, private spreadsheets, or user profiles.
- Discuss any telemetry, networking, dependency, permission, or storage-format change before implementing it.
- Update the user guide and privacy documentation when behavior or data handling changes. Use English for public documentation.

## Verification checklist

State what you actually ran, with output or observations. A successful compile is not a runtime test, and a universal build is not Intel runtime verification. Automated core and native UI-construction checks ran on Apple Silicon; end-to-end permission flows and Intel runtime behavior are not release-validated.

Run `./scripts/test.sh` and `python3 scripts/check_release.py` after packaging. See [TESTING.md](docs/TESTING.md) for the full validation checklist.

For UI changes, manually check with non-sensitive content:

1. Single-instance launch, D drag/position, Show D toggle, and Open at Login toggle.
2. AX permission denied/granted, window enumeration, focus, minimized restore, and save-prompt behavior when closing a window.
3. Middle-click add/toggle-remove; persistence across restart; numbering after removal.
4. Best-effort reopening for changed/duplicate titles and missing windows/apps; no silent claim of exact restoration.
5. Links to visible/minimized/hidden apps, endpoint opening/removal, and badge/dialog heuristic state.
6. Escape/empty-space dismissal, small displays, multiple displays, and two-column truncation.
7. Optional browser colors with Screen Recording denied/granted and optional Tailscale absent/present.
8. Native middle-click behavior restored after **Quit DDD**. Show D off intentionally does not stop interception.

Report untested cases explicitly. Keep runtime evidence separate from build, packaging, or checksum verification. The private `_AXUIElementGetWindow` SPI is an OS-compatibility risk and an App Store distribution blocker, not a stable public API.
