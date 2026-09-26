#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"

DEFAULT_BUILD_NUMBER="$(
  git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || true
)"
BUILD_NUMBER="${TELEPHONE_BUILD_NUMBER:-${DEFAULT_BUILD_NUMBER:-143}}"

DEFAULT_BUILD_COMMIT="$(
  git -C "$ROOT_DIR" rev-parse --short=7 HEAD 2>/dev/null || true
)"
BUILD_COMMIT="${TELEPHONE_BUILD_COMMIT:-${DEFAULT_BUILD_COMMIT:-local}}"

"$ROOT_DIR/script/bootstrap_third_party.sh"
mkdir -p "$BUILD_DIR"

XCODEBUILD_ARGS=(
  -project "$ROOT_DIR/Telephone.xcodeproj"
  -target Telephone
  -configuration "$CONFIGURATION"
  -sdk macosx
  "ARCHS=arm64"
  "ONLY_ACTIVE_ARCH=YES"
  "SYMROOT=$BUILD_DIR"
  "OBJROOT=$BUILD_DIR/Intermediates.noindex"
  "DEVELOPMENT_TEAM="
  "CODE_SIGNING_ALLOWED=NO"
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
  "TELEPHONE_BUILD_COMMIT=$BUILD_COMMIT"
)

if [[ -n "${TELEPHONE_MARKETING_VERSION:-}" ]]; then
  XCODEBUILD_ARGS+=(
    "MARKETING_VERSION=$TELEPHONE_MARKETING_VERSION"
  )
fi

exec xcodebuild "${XCODEBUILD_ARGS[@]}" build
