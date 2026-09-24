#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/AppIntentsTestDerivedData"
MODE="${1:-test}"

COMMON_ARGS=(
  -project "$ROOT_DIR/Telephone.xcodeproj"
  -scheme "TelephoneAppIntentsTests"
  -destination "platform=macOS"
  -derivedDataPath "$DERIVED_DATA"
)

case "$MODE" in
  test)
    xcodebuild "${COMMON_ARGS[@]}" test
    ;;
  --build-only-unsigned)
    xcodebuild       "${COMMON_ARGS[@]}"       DEVELOPMENT_TEAM=""       CODE_SIGNING_ALLOWED=NO       build-for-testing
    ;;
  *)
    echo "Usage: $0 [--build-only-unsigned]" >&2
    exit 64
    ;;
esac
