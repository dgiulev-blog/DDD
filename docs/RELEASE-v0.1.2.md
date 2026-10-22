# DDD v0.1.2 — Separate clickable job boxes

Hover over D to see each linked job in its own rounded box.

- **Left-click** a box to reopen the job.
- **Right-click** a box to remove that saved job and its visual link. This does not quit the app or close its window.
- Remaining jobs renumber and the counts/links refresh immediately.
- Separate borders, padding, and hover highlighting make each target clear.
- Long queues remain scrollable.

Download `DDD-0.1.2-macos-universal.zip` and `SHA256SUMS.txt`. Verify with
`shasum -a 256 -c SHA256SUMS.txt`; quit the old DDD and move the extracted app into Applications.
Requires macOS 14+. Contains Apple Silicon and Intel slices.

Native regression checks cover left-click opening, right-click removal targeting,
no accidental open on right-click, renumbering, 60-job scrolling, and delayed hover lifecycle.
The actual native list was rendered with synthetic jobs and visually inspected on Apple Silicon.
Intel runtime and fresh-user permission/Gatekeeper flows remain unvalidated.

**Experimental, ad-hoc signed, not notarized.** Gatekeeper may block it. Use Open Anyway
only if offered by macOS and you trust the verified download, or build from source.
Do not disable system-wide protections. DDD still intercepts middle-clicks globally
until quit, and follow-up data remains local plaintext. No data format changes.
