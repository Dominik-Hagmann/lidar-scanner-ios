#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
generate=false
check_only=false
open_project=false
for option in "$@"; do
    case "$option" in
        --check) check_only=true ;;
        --regenerate-project) generate=true ;;
        --open) open_project=true ;;
        --help|-h)
            echo "Usage: bash scripts/setup.sh [--check] [--open] [--regenerate-project]"
            echo "Default: prepare native libraries and locked Swift packages; preserve the existing Xcode project."
            echo "--check checks prerequisites without downloading or changing project files."
            echo "--regenerate-project backs up and regenerates the Xcode project (requires XcodeGen)."
            exit 0 ;;
        *) echo "Unknown option: $option (use --help)." >&2; exit 2 ;;
    esac
done
[[ -f LiDARScanner.xcodeproj/project.pbxproj ]] || generate=true
if $generate; then
    bash scripts/check-setup.sh --generate-project
else
    bash scripts/check-setup.sh
fi
$check_only && exit 0

lockfile=LiDARScanner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
if [[ ! -f "$lockfile" ]]; then
    echo "The committed Swift package lockfile is missing: $lockfile. Restore it from this repository before setup." >&2
    exit 1
fi
python3 scripts/prepare-gaussians.py
if $generate; then
    mkdir -p Dependencies/preserved
    backup="$(mktemp -d "$project_root/Dependencies/preserved/xcode-project-XXXXXX")"
    cp -R LiDARScanner.xcodeproj "$backup/"
    echo "Previous Xcode project preserved at $backup/LiDARScanner.xcodeproj"
    if ! xcodegen generate; then
        echo "Project generation failed. The original project remains in $backup." >&2
        exit 1
    fi
    # Project generation must not discard the committed dependency lock.
    mkdir -p "$(dirname "$lockfile")"
    cp "$backup/$lockfile" "$lockfile"
    echo "Project regenerated. Recheck your Team before deploying to an existing app."
fi
xcodebuild -resolvePackageDependencies -project LiDARScanner.xcodeproj \
    -scheme LiDARScanner -onlyUsePackageVersionsFromResolvedFile
echo "Setup complete. Open LiDARScanner.xcodeproj, choose your Team and physical iPhone, then Run."
$open_project && open LiDARScanner.xcodeproj
exit 0
