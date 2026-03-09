#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DESTINATION="${METALCRAFT_DESTINATION:-}"

COMMAND=(
  xcodebuild
  -project Metalcraft.xcodeproj
  -scheme MetalcraftApp
  -configuration Debug
  build
)

if [[ -n "${METALCRAFT_DERIVED_DATA_PATH:-}" ]]; then
  COMMAND+=(-derivedDataPath "${METALCRAFT_DERIVED_DATA_PATH}")
fi

if [[ -n "$DESTINATION" ]]; then
  COMMAND+=(-destination "$DESTINATION")
fi

if [[ "${CI:-false}" == "true" ]]; then
  COMMAND+=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGN_IDENTITY=")
fi

"${COMMAND[@]}"
