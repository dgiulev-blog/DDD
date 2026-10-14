# Testing and release checks

## Automated checks

On macOS with Xcode Command Line Tools installed:

```sh
./scripts/test.sh
./scripts/package.sh
python3 scripts/check_release.py
```

The Swift checks exercise follow-up identity and JSON round trips, text cleanup,
app categorization, VNC URL construction, and radial layout at screen edges.
They do not initialize the follow-up store, grant permissions, or replace the
installed app. The release checker verifies metadata, code signature integrity,
both universal binary slices, archive contents, checksums, and local Markdown links.
Its private-value scan is heuristic, not a security audit.

## Manual acceptance checklist

Use a separate macOS user account with disposable documents and test chats.
Do not test destructive right-click actions on unsaved production work.

- Install into Applications; launch once; verify a menu-bar icon and movable D.
- Grant Accessibility yourself. Confirm app/window enumeration and restoring a minimized window.
- Open the D; select a single-window app and a multi-window app. Dismiss with Escape.
- Middle-click two test places. Verify badges, lines, and re-opening each place.
- Middle-click the same place again; verify removal and contiguous renumbering.
- Test two different chats in one app, and two browser URLs. Restoration is best effort.
- Click a line-end ring; hover to see details; right-click to remove only that follow-up.
- Right-click a disposable window pill to close it. Right-click an app bubble to quit it.
- Toggle Show D. Note that it hides UI but does **not** disable middle-click interception.
- Quit DDD and confirm the mouse middle button returns to its ordinary behavior.
- Deny Screen Recording: core functions should still work with default pill colors.
- If desired, grant Screen Recording yourself; check browser theme sampling.
- Verify Open at Login settings and login behavior in the test user account.
- If using Tailscale, verify peers and VNC with a machine you are authorized to access.
- Test with multiple displays, display removal, Spaces, and full-screen applications.
- Test on macOS 14 and Intel hardware before describing either as runtime-validated.

## v0.1.0 validation scope

See the GitHub release notes for execution results. Universal cross-compilation
is not evidence of a runtime test on Intel. Automated checks do not prove all
third-party accessibility trees, deep links, permission flows, or Gatekeeper behavior.
