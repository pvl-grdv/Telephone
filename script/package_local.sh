#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-local}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/Release/Telephone.app"
ENTITLEMENTS="$ROOT_DIR/Telephone/Telephone.local.entitlements"
SIGN_IDENTITY="${TELEPHONE_CODE_SIGN_IDENTITY:--}"
ARCHIVE="$DIST_DIR/Telephone-$VERSION-local.zip"

"$ROOT_DIR/script/build.sh" Release

echo "Signing Telephone with identity: $SIGN_IDENTITY"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

/usr/bin/codesign \
  --force \
  --deep \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_BUNDLE"

SIGNED_ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" 2>&1)"
grep -q "com.apple.security.app-sandbox" <<<"$SIGNED_ENTITLEMENTS"
grep -q "com.apple.security.network.client" <<<"$SIGNED_ENTITLEMENTS"
grep -q "com.apple.security.network.server" <<<"$SIGNED_ENTITLEMENTS"
grep -q "com.apple.security.device.microphone" <<<"$SIGNED_ENTITLEMENTS"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

/usr/bin/ditto   -c   -k   --sequesterRsrc   --keepParent   "$APP_BUNDLE"   "$ARCHIVE"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "$ARCHIVE"
