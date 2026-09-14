#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
xcodegen generate
open LiDARScanner.xcodeproj
