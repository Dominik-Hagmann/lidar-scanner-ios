#!/bin/bash
set -euo pipefail
simulator_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcodebuild test -project LiDARScanner.xcodeproj -scheme LiDARScanner \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -resultBundlePath build/ScanTests.xcresult CODE_SIGNING_ALLOWED=NO
