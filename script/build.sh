#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"

"$ROOT_DIR/script/bootstrap_third_party.sh"

mkdir -p "$BUILD_DIR"

exec xcodebuild   -project "$ROOT_DIR/Telephone.xcodeproj"   -target Telephone   -configuration "$CONFIGURATION"   -sdk macosx   ARCHS=arm64   ONLY_ACTIVE_ARCH=YES   SYMROOT="$BUILD_DIR"   OBJROOT="$BUILD_DIR/Intermediates.noindex"   DEVELOPMENT_TEAM=""   CODE_SIGNING_ALLOWED=NO   build
