#!/bin/bash
set -euo pipefail
ISLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
ISLA_BUILD="${ISLA_BUILD_DIR:-$ISLA_ROOT/build}"
ISLA_APP="$ISLA_BUILD/ISLA.app"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "ISLA requiere macOS para compilar." >&2
    exit 1
fi
ISLA_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
ISLA_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
if (( ${ISLA_SDK_VERSION%%.*} < 26 )); then
    echo "Se necesita el SDK de macOS 26 o posterior. Instala Xcode 26+ o sus herramientas de línea de comandos." >&2
    exit 1
fi
mkdir -p "$ISLA_BUILD/module-cache" "$ISLA_APP/Contents/MacOS" "$ISLA_APP/Contents/Resources"
for ISLA_ARCH in arm64 x86_64; do
    xcrun --sdk macosx swiftc -swift-version 5 -O -sdk "$ISLA_SDK_PATH" \
        -module-cache-path "$ISLA_BUILD/module-cache" -target "$ISLA_ARCH-apple-macosx14.0" \
        -framework AppKit -framework SwiftUI -framework CoreAudio -framework IOKit \
        -framework QuartzCore -framework EventKit \
        "$ISLA_ROOT"/Sources/*.swift -o "$ISLA_BUILD/ISLA-$ISLA_ARCH"
done
lipo -create "$ISLA_BUILD/ISLA-arm64" "$ISLA_BUILD/ISLA-x86_64" -output "$ISLA_APP/Contents/MacOS/ISLA"
cp "$ISLA_ROOT/Info.plist" "$ISLA_APP/Contents/Info.plist"
cp "$ISLA_ROOT/Resources/AppIcon.icns" "$ISLA_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$ISLA_APP"
codesign --verify --deep --strict "$ISLA_APP"
"$ISLA_APP/Contents/MacOS/ISLA" --self-test
printf 'Compilación universal lista: %s\n' "$ISLA_APP"
