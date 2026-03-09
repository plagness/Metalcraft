#!/bin/bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found; installing with Homebrew"
  brew install xcodegen
else
  echo "xcodegen already installed"
fi
