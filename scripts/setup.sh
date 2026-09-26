#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
bash scripts/prepare-gaussians.sh
xcodegen generate
echo "Open LiDARScanner.xcodeproj and run LiDARScanner on your iPhone."
