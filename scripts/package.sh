#!/bin/bash
# A source-built archive, never a copy of /Applications or user data.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHS='arm64 x86_64' ./build.sh
VERSION="$(tr -d '\n' < VERSION)"
mkdir -p dist
ARCHIVE="dist/DDD-$VERSION-macos-universal.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent build/DDD.app "$ARCHIVE"
(cd dist && shasum -a 256 "$(basename "$ARCHIVE")" > SHA256SUMS.txt)
printf 'Packaged %s\n' "$ARCHIVE"
