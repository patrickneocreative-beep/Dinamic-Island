#!/bin/bash
set -euo pipefail
ISLA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISLA_BUILD="${ISLA_BUILD_DIR:-$ISLA_ROOT/build}"
ISLA_DIST="$ISLA_ROOT/dist"
ISLA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ISLA_ROOT/Info.plist")"
if [[ ! "$ISLA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Versión inválida en Info.plist." >&2; exit 1
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --skip-build ) ]]; then
    echo "Uso: bash scripts/package.sh [--skip-build]" >&2; exit 1
fi
if [[ "${1:-}" != --skip-build ]]; then bash "$ISLA_ROOT/build.sh"; fi
ISLA_APP="$ISLA_BUILD/ISLA.app"
ISLA_BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ISLA_APP/Contents/Info.plist")"
if [[ "$ISLA_BUILT_VERSION" != "$ISLA_VERSION" ]]; then echo "La app no coincide con Info.plist; compila de nuevo." >&2; exit 1; fi
codesign --verify --deep --strict "$ISLA_APP"
for ISLA_ARCH in arm64 x86_64; do
    lipo "$ISLA_APP/Contents/MacOS/ISLA" -verify_arch "$ISLA_ARCH"
done
mkdir -p "$ISLA_DIST"
ISLA_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/isla-package.XXXXXX")"
trap 'rm -rf "$ISLA_STAGE"' EXIT
mkdir -p "$ISLA_STAGE/ISLA"
# Exclude extended attributes and Finder metadata from public artifacts.
ditto --norsrc --noextattr "$ISLA_APP" "$ISLA_STAGE/ISLA/ISLA.app"
cp "$ISLA_ROOT/LICENSE" "$ISLA_STAGE/ISLA/LICENSE"
cp "$ISLA_ROOT/docs/INSTALL.md" "$ISLA_STAGE/ISLA/INSTALACION.md"
cp "$ISLA_ROOT/PRIVACY.md" "$ISLA_STAGE/ISLA/PRIVACIDAD.md"
codesign --verify --deep --strict "$ISLA_STAGE/ISLA/ISLA.app"
ISLA_ARCHIVE="ISLA-$ISLA_VERSION-macOS-universal.zip"
ditto -c -k --norsrc --noextattr --keepParent "$ISLA_STAGE/ISLA" "$ISLA_DIST/$ISLA_ARCHIVE"
(cd "$ISLA_DIST" && shasum -a 256 "$ISLA_ARCHIVE" > SHA256SUMS.txt)
printf 'Paquete listo: %s/%s\n' "$ISLA_DIST" "$ISLA_ARCHIVE"
