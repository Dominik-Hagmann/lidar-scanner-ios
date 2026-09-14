#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
compiler="${CXX:-c++}"
"$compiler" -std=c++17 -Wall -Wextra -Werror -pedantic -g \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  "$project_root/LiDARScanner/Core/PointCloudCore.cpp" "$project_root/Tests/test_core.cpp" \
  -o "$test_root/test_core"
"$test_root/test_core" "$test_root/exports"
python3 "$project_root/Tests/check_exports.py" "$test_root/exports"
