#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT_DIR/build/Telephone-active-call.trace}"
DURATION="${TRACE_DURATION:-45s}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required to record an Instruments trace." >&2
  exit 1
fi

if ! pgrep -x Telephone >/dev/null 2>&1; then
  echo "Telephone is not running. Launch it before recording." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"

cat <<EOF
Recording Telephone with the SwiftUI Instruments template for $DURATION.
Start or answer a call while recording. The app marks the active-call window
with the CallPerformance / ActiveCall signpost interval.
EOF

xcrun xctrace record   --template "SwiftUI"   --attach "Telephone"   --time-limit "$DURATION"   --output "$OUTPUT"

echo "Trace saved to: $OUTPUT"
echo "Open it with: open \"$OUTPUT\""
