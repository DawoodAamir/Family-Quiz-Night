#!/bin/bash
set -euo pipefail
platform="${1:-tvOS}"
case "$platform" in
  tvOS) scheme='Family Quiz Night'; device_platform='tvOS Simulator' ;;
  iOS) scheme='Family Quiz Controller'; device_platform='iOS Simulator' ;;
  *) echo 'Choose iOS or tvOS.' >&2; exit 2 ;;
esac
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
simulator_id="${SIMULATOR_UDID:-$(python3 - "$platform" <<'PY'
import json,sys
from pathlib import Path
for runtime, devices in json.loads(Path('build/simulators.json').read_text())['devices'].items():
    if sys.argv[1]+'-27' in runtime:
        for device in devices:
            if device.get('isAvailable'):
                print(device['udid']); raise SystemExit
raise SystemExit('Install the requested OS 27 simulator runtime in Xcode.')
PY
)}"
xcrun simctl bootstatus "$simulator_id" -b
result="build/$platform-$(date +%s).xcresult"
trap 'if [ -d "$result" ]; then xcrun xcresulttool export attachments --path "$result" --output-path "build/Screenshots-$platform" || true; fi' EXIT
xcodebuild -project 'Family Quiz Night.xcodeproj' -scheme "$scheme" -destination "platform=$device_platform,id=$simulator_id" -derivedDataPath build/DerivedData test -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath "$result"
