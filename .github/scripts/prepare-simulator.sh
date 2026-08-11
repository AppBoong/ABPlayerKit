#!/bin/bash
# Selects an available iPhone simulator for xcodebuild against the resolved
# $DEVELOPER_DIR toolchain, downloading the iOS platform and creating a
# device from scratch if the runner image has no iOS runtime installed at
# all (observed on macos-15 runner-image drift against a pinned Xcode).
# Writes DESTINATION=platform=iOS Simulator,id=<udid> to $GITHUB_ENV.
set -euo pipefail

preferred_name="${PREFERRED_SIMULATOR_NAME:-iPhone 16 Pro}"

select_udid() {
  python3 - "$preferred_name" <<'PY'
import json
import subprocess
import sys

preferred = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            candidates.append((runtime, device["name"], device["udid"]))

for _runtime, name, udid in candidates:
    if name == preferred:
        print(udid)
        sys.exit(0)

# No exact name match: fall back to any iPhone simulator on the newest
# available iOS runtime.
candidates.sort(key=lambda c: c[0], reverse=True)
if candidates:
    print(candidates[0][2])
PY
}

udid="$(select_udid || true)"

if [ -z "$udid" ]; then
  echo "No available iPhone simulator found; checking for an installed iOS runtime..."
  if ! xcrun simctl list runtimes available | grep -q "iOS "; then
    echo "No iOS simulator runtime installed; downloading the iOS platform (this can take several minutes)..."
    xcodebuild -downloadPlatform iOS
  fi

  runtime_id="$(xcrun simctl list runtimes available -j | python3 -c '
import json
import sys

runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
runtimes.sort(key=lambda r: r["version"])
print(runtimes[-1]["identifier"])
')"

  device_type_id="$(xcrun simctl list devicetypes -j | python3 -c '
import json
import sys

types = [t for t in json.load(sys.stdin)["devicetypes"] if t["name"].startswith("iPhone")]
pro = [t for t in types if "Pro" in t["name"]]
chosen = pro[-1] if pro else types[-1]
print(chosen["identifier"])
')"

  echo "Creating a simulator from device type $device_type_id / runtime $runtime_id..."
  udid="$(xcrun simctl create "CI iPhone" "$device_type_id" "$runtime_id")"
fi

name="$(xcrun simctl list devices -j | python3 -c '
import json
import sys

target = "'"$udid"'"
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == target:
            print(device["name"])
            sys.exit(0)
')"

echo "Selected simulator: $name ($udid)"
echo "DESTINATION=platform=iOS Simulator,id=$udid" >> "$GITHUB_ENV"
