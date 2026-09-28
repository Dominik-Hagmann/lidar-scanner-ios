#!/bin/bash
# Prepare and verify the pinned native dependency without regenerating Xcode files.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_root/scripts/check-setup.sh"
python3 "$project_root/scripts/prepare-gaussians.py"
