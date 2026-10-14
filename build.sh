#!/bin/bash
# Build only. Never replace an installed app or launch it implicitly.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '\n' < VERSION)"
ARCHS="${ARCHS:-$(uname -m)}"
SIGN_ID="${SIGN_ID:--}"
APP="build/DDD.app"
mkdir -p build
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
BINARIES=()
for ARCH in $ARCHS; do
    case "$ARCH" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
    BINARY="build/DDD-$ARCH"
    xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos14.0" Sources/*.swift -o "$BINARY"
    BINARIES+=("$BINARY")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DDD"
python3 scripts/info_plist.py "$VERSION" "$APP/Contents/Info.plist"
if [[ "$SIGN_ID" == '-' ]]; then
    codesign --force --sign - --identifier io.prim.ddd "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" --identifier io.prim.ddd "$APP"
fi
codesign --verify --strict "$APP"
printf 'Built %s (%s; signature: %s). Not installed or launched.\n' "$APP" "$ARCHS" "$SIGN_ID"
