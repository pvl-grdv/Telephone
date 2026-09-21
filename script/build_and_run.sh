#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Telephone"
BUNDLE_ID="com.tlphn.Telephone"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ENTITLEMENTS="$ROOT_DIR/Telephone/Telephone.local.entitlements"
SIGN_IDENTITY="${TELEPHONE_CODE_SIGN_IDENTITY:--}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "Signing Telephone with identity: $SIGN_IDENTITY"

"$ROOT_DIR/script/build.sh" Debug

/usr/bin/codesign \
  --force \
  --deep \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
