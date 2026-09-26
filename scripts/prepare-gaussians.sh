#!/bin/bash
# Build the pinned, source-available engine. This runs on the developer's Mac,
# never on the phone. Scanning and training do not make network requests.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
engine_root="$project_root/Dependencies/msplat"
revision=e8611098583059b82e0b7d35259fb4e9c42df248
if [[ ! -d "$engine_root/.git" ]]; then
    mkdir -p "$project_root/Dependencies"
    GIT_LFS_SKIP_SMUDGE=1 git clone --no-checkout https://github.com/frs0n/msplat-ios.git "$engine_root"
fi
if [[ "$(git -C "$engine_root" rev-parse HEAD)" != "$revision" ]]; then
    git -C "$engine_root" fetch origin "$revision"
fi
GIT_LFS_SKIP_SMUDGE=1 git -C "$engine_root" checkout --detach "$revision"
python3 "$project_root/scripts/patch-engine.py" "$engine_root"
stamp="$engine_root/.scanner-build-5"
if [[ ! -f "$stamp" || ! -d "$engine_root/MsplatCore.xcframework" ]]; then
    bash "$engine_root/scripts/build-xcframework.sh"
    touch "$stamp"
fi
