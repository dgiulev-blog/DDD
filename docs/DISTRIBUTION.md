# Distribution and maintenance

DDD is MIT licensed. Source and downloadable app releases live at
https://github.com/dgiulev-blog/DDD.

## Current distribution status

Version 0.1.1 is an **experimental, ad-hoc-signed, unnotarized** release.
The universal executable contains Apple Silicon (`arm64`) and Intel (`x86_64`)
slices targeting macOS 14.0+. Cross-compilation does not constitute runtime
validation on every supported system.

The app is not sandboxed and uses a private Accessibility SPI for window IDs.
This is a direct-download project, not an App Store-ready submission.

## Reproduce a release

Requires macOS, Xcode Command Line Tools (`xcode-select --install`), Python 3,
and the command-line tools shipped with macOS. No third-party Swift packages.

```sh
./scripts/test.sh
./scripts/package.sh
python3 scripts/check_release.py
```

Outputs:
- `build/DDD.app`
- `dist/DDD-0.1.1-macos-universal.zip` (version comes from `VERSION`)
- `dist/SHA256SUMS.txt`

The build script builds only. It never replaces `/Applications/DDD.app`,
launches the app, reads local follow-up data, or resets permissions.
The ZIP is built from this source tree, not from the maintainer's installed app.

Signing timestamps, compiler versions, and platform SDKs can change output bytes.
This is a reproducible *procedure*, not a claim of byte-for-byte reproducible builds.

## Check a download

Put the ZIP and checksum file from the **same release** in one directory:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

A checksum detects accidental corruption; a checksum published beside a malicious
file does not establish independent trust. An ad-hoc code signature verifies
bundle integrity, not the developer's identity.

## Maintainer release gate

1. Update `VERSION` and `CHANGELOG.md`.
2. Run automated checks and the manual checklist in [TESTING.md](TESTING.md).
3. Review the exact staged files. Never include user data, Claude transcripts,
   private screenshots, certificates, or signing secrets.
4. Commit and tag the reviewed source. Require green GitHub build checks.
5. Attach the ZIP and `SHA256SUMS.txt` to the tag's GitHub release.
6. Mark experimental releases as prereleases. Explain signing and validation scope.
7. Re-download assets and verify their checksums and code signature.

CI builds and validates pull requests and pushes; it does not automatically publish
new releases. GitHub Actions artifacts are not a substitute for release downloads.

## Removing the Gatekeeper friction

The maintainer needs an Apple Developer Program membership and a valid
**Developer ID Application** signing identity. The current development identity
is not enough. Do not distribute private keys or signing certificates in git.

`SIGN_ID='Developer ID Application: …' ./scripts/package.sh` requests hardened
runtime and timestamped signing instead of ad-hoc signing. A real distribution
process must then notarize the ZIP using `xcrun notarytool`, inspect Apple's
result, staple the accepted ticket to the app, re-create the ZIP, and regenerate
the checksums. Only claim notarization after Apple's successful response and
local Gatekeeper verification. This workflow has **not** been exercised for 0.1.1
because no valid distribution identity is available on the build host.

Do not instruct users to disable Gatekeeper system-wide. A future signed and
notarized release remains necessary for a smoother mainstream installation.
