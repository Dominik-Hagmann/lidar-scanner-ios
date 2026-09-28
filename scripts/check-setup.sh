#!/bin/bash
# Read-only prerequisite check. Pass --generate-project when XcodeGen is needed.
set -euo pipefail
generate=false
case "${1:-}" in
    '') ;;
    --generate-project) generate=true ;;
    *) echo "Usage: bash scripts/check-setup.sh [--generate-project]" >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin ]]; then
    echo "App setup requires macOS with the full Xcode application." >&2
    exit 1
fi

missing=()
for tool in git git-lfs cmake python3 xcodebuild xcode-select xcrun; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if $generate && ! command -v xcodegen >/dev/null 2>&1; then
    missing+=(xcodegen)
fi
if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing command: %s\n' "${missing[@]}" >&2
    echo "Install the full Xcode application and complete its first launch." >&2
    echo "With Homebrew installed: brew install cmake git-lfs" >&2
    $generate && echo "Project generation also needs: brew install xcodegen" >&2
    echo "If tools are installed, make sure their bin directory is on PATH." >&2
    exit 1
fi

git lfs version >/dev/null || { echo "Git LFS is installed but cannot run." >&2; exit 1; }
python3 -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9 or newer is required"'
cmake_version="$(cmake --version | head -n 1)"
python3 - "$cmake_version" <<'PY'
import re, sys
match = re.search(r'(\d+)\.(\d+)', sys.argv[1])
if not match or tuple(map(int, match.groups())) < (3, 21):
    sys.exit('CMake 3.21 or newer is required. Update CMake before running setup.')
PY
if ! xcode_version="$(xcodebuild -version)"; then
    echo "Select the full Xcode installation and complete its first launch before retrying." >&2
    exit 1
fi
echo "$xcode_version"
python3 - "$xcode_version" <<'PY'
import re, sys
match = re.search(r'Xcode (\d+)\.(\d+)', sys.argv[1])
if not match or tuple(map(int, match.groups())) < (16, 4):
    sys.exit('Xcode 16.4 or newer is required. Select a supported full Xcode installation.')
PY
for sdk in macosx iphoneos iphonesimulator; do
    if ! xcrun --sdk "$sdk" --show-sdk-path >/dev/null; then
        echo "The $sdk SDK is unavailable in the selected Xcode installation." >&2
        exit 1
    fi
    if ! metal_status="$(xcrun --sdk "$sdk" metal --version 2>&1)"; then
        printf '%s\n' "$metal_status" >&2
        echo "The Metal compiler is unavailable for $sdk. Complete Xcode's component installation; see docs/TROUBLESHOOTING.md." >&2
        exit 1
    fi
done
echo "Prerequisites available. No project files or dependencies were changed."
