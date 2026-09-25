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

verify_team_identifier() {
  local bundle_path="$1"
  local expected_team="$2"
  local details

  details="$(codesign -dvvv "$bundle_path" 2>&1)"
  printf '%s\n' "$details"

  if ! grep -Fq "TeamIdentifier=$expected_team" <<<"$details"; then
    echo "$bundle_path was not signed with TeamIdentifier=$expected_team" >&2
    exit 1
  fi
}

case "$MODE" in
  test)
    xcodebuild "${COMMON_ARGS[@]}" test
    ;;
  --build-only-unsigned)
    xcodebuild \
      "${COMMON_ARGS[@]}" \
      DEVELOPMENT_TEAM="" \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing
    ;;
  --signed-development)
    : "${TELEPHONE_DEVELOPMENT_TEAM:?TELEPHONE_DEVELOPMENT_TEAM is required}"
    : "${TELEPHONE_CODE_SIGN_IDENTITY:?TELEPHONE_CODE_SIGN_IDENTITY is required}"

    SIGNING_ARGS=(
      DEVELOPMENT_TEAM="$TELEPHONE_DEVELOPMENT_TEAM"
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$TELEPHONE_CODE_SIGN_IDENTITY"
    )

    if [[ -n "${TELEPHONE_SIGNING_KEYCHAIN:-}" ]]; then
      SIGNING_ARGS+=(
        "OTHER_CODE_SIGN_FLAGS=--keychain $TELEPHONE_SIGNING_KEYCHAIN"
      )
    fi

    xcodebuild \
      "${COMMON_ARGS[@]}" \
      "${SIGNING_ARGS[@]}" \
      build-for-testing

    verify_team_identifier \
      "$DERIVED_DATA/Build/Products/Debug/Telephone.app" \
      "$TELEPHONE_DEVELOPMENT_TEAM"
    verify_team_identifier \
      "$DERIVED_DATA/Build/Products/Debug/TelephoneAppIntentsTests-Runner.app" \
      "$TELEPHONE_DEVELOPMENT_TEAM"

    xcodebuild \
      "${COMMON_ARGS[@]}" \
      "${SIGNING_ARGS[@]}" \
      test-without-building
    ;;
  *)
    echo "Usage: $0 [--build-only-unsigned|--signed-development]" >&2
    exit 64
    ;;
esac
