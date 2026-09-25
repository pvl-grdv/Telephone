#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/UITestDerivedData"

"$ROOT_DIR/script/bootstrap_third_party.sh"

xcodebuild \
  -project "$ROOT_DIR/Telephone.xcodeproj" \
  -scheme "TelephoneAppIntentsTests" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  -only-testing:TelephoneAppIntentsTests/TelephoneUISmokeTests \
  test
