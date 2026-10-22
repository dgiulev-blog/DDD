# DDD v0.1.1 — All linked jobs on hover

Hover over the floating **D** for a short moment to see every linked job in one list:

- Number, app name, and job label for every saved follow-up.
- Scrollable list for long queues; no two-column truncation in this view.
- Click a row to reopen the job using the existing best-effort navigation.
- Move into the list to use it; move away to dismiss it.
- Clicking/dragging D still uses the existing picker/drag controls.
- Explicit “No linked jobs” empty state.

## Install

Download `DDD-0.1.1-macos-universal.zip` and `SHA256SUMS.txt`, verify with
`shasum -a 256 -c SHA256SUMS.txt`, quit the old DDD, and move the extracted
app into Applications. Requires macOS 14+; the binary contains Apple Silicon
and Intel slices. See the [user guide](https://github.com/dgiulev-blog/DDD/blob/main/docs/USER-GUIDE.md).

## Validation

Core regression checks pass, including a 60-job scrollable list, row numbering,
last-row actions, empty state, D pointer tracking, actual delayed hover-panel
opening, close, and cancellation. The list was rendered with synthetic data
and visually inspected on Apple Silicon. Universal build, bundle signature
integrity, packaging, checksums, and documentation checks pass.

Intel runtime and fresh-user permission/Gatekeeper flows are not validated.

## Existing experimental limitations

The public build remains **ad-hoc signed and unnotarized**; Gatekeeper may block
it. Only use Open Anyway if macOS offers it and you trust the verified source,
or build from source. Do not disable system-wide protections.

DDD intercepts middle-clicks system-wide even with Show D off; quit DDD to
restore ordinary middle-click behavior. Follow-ups are local plaintext and may
contain sensitive titles and URLs. Reopening remains best effort. No existing
follow-up data format or permissions have been changed by this feature.
