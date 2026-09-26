#!/bin/bash
set -euo pipefail

objective_c_sources="$(
  find Telephone -type f \( -name '*.m' -o -name '*.mm' \) -print | sort
)"

if [[ -n "$objective_c_sources" ]]; then
  echo "Telephone application code must remain Swift-only." >&2
  printf '%s\n' "$objective_c_sources" >&2
  exit 1
fi

echo "Swift-only application source check passed."
