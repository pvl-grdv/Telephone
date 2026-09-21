#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/TestDerivedData"

run_tests() {
  local scheme="$1"
  xcodebuild     -project "$ROOT_DIR/Telephone.xcodeproj"     -scheme "$scheme"     -destination "platform=macOS"     -derivedDataPath "$DERIVED_DATA"     DEVELOPMENT_TEAM=""     CODE_SIGNING_ALLOWED=NO     test
}

run_tests Domain
run_tests UseCasesTests
