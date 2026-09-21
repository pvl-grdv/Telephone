#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-local}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/Release/Telephone.app"
ENTITLEMENTS="$ROOT_DIR/Telephone/Telephone.entitlements"
ARCHIVE="$DIST_DIR/Telephone-$VERSION-local.zip"

"$ROOT_DIR/script/build.sh" Release

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

/usr/bin/codesign   --force   --deep   --sign -   --entitlements "$ENTITLEMENTS"   "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

/usr/bin/ditto   -c   -k   --sequesterRsrc   --keepParent   "$APP_BUNDLE"   "$ARCHIVE"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "$ARCHIVE"
