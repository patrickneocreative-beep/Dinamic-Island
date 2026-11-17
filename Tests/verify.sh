#!/bin/bash
set -euo pipefail
ISLA_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISLA_TEST_BUILD="$ISLA_TEST_ROOT/build/verification"
mkdir -p "$ISLA_TEST_BUILD/module-cache"
ISLA_TEST_SOURCES=()
for ISLA_TEST_FILE in "$ISLA_TEST_ROOT"/Sources/*.swift; do
    if [[ "$(basename "$ISLA_TEST_FILE")" != "IslaApp.swift" ]]; then
        ISLA_TEST_SOURCES+=("$ISLA_TEST_FILE")
    fi
done
swiftc -swift-version 5 -Onone -module-cache-path "$ISLA_TEST_BUILD/module-cache" \
    -framework AppKit -framework SwiftUI -framework CoreAudio -framework IOKit -framework QuartzCore -framework EventKit \
    "${ISLA_TEST_SOURCES[@]}" "$ISLA_TEST_ROOT/Tests/VerifyIsla.swift" -o "$ISLA_TEST_BUILD/verify-isla"
"$ISLA_TEST_BUILD/verify-isla" "${1:-$ISLA_TEST_BUILD/captures}" "${@:2}"
