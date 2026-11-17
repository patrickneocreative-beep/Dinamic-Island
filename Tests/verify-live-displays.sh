#!/bin/bash
set -euo pipefail
ISLA_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISLA_TEST_BUILD="$ISLA_TEST_ROOT/build/live-display-verification"
mkdir -p "$ISLA_TEST_BUILD/module-cache"
swiftc -parse-as-library -module-cache-path "$ISLA_TEST_BUILD/module-cache" \
    "$ISLA_TEST_ROOT/Tests/VerifyLiveDisplays.swift" -o "$ISLA_TEST_BUILD/verify-live-displays"
"$ISLA_TEST_BUILD/verify-live-displays"
