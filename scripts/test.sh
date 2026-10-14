#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SOURCES=()
for FILE in Sources/*.swift; do
    [[ "$FILE" == Sources/main.swift ]] || SOURCES+=("$FILE")
done
xcrun swiftc -swift-version 5 "${SOURCES[@]}" Tests/main.swift -o build/core-tests
./build/core-tests
