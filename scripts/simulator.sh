#!/bin/zsh
# 用法：scripts/simulator.sh [run|test]；可用 NEODIZZY_SIMULATOR 指定 UDID。
set -euo pipefail
ROOT=${0:A:h:h}
ACTION=${1:-run}
[[ $ACTION == run || $ACTION == test ]] || { echo "用法：$0 [run|test]" >&2; exit 64; }
DEVICES=$(mktemp -t neodizzy-simulators)
trap 'rm -f "$DEVICES"' EXIT
xcrun simctl list devices available --json > "$DEVICES"
SIM=${NEODIZZY_SIMULATOR:-$(python3 - "$DEVICES" <<'PY2'
import json, sys
candidates = [d for runtime, group in json.load(open(sys.argv[1]))['devices'].items()
              if 'iOS-27' in runtime for d in group if d['name'].startswith('iPhone')]
candidates.sort(key=lambda d: d['state'] != 'Booted')
if not candidates:
    raise SystemExit('请在 Xcode 中安装 iOS 27 模拟器。')
print(candidates[0]['udid'])
PY2
)}
STATE=$(xcrun simctl list devices booted --json)
if ! print -r -- "$STATE" | python3 -c 'import json,sys; sys.exit(not any(d["udid"] == sys.argv[1] for g in json.load(sys.stdin)["devices"].values() for d in g))' "$SIM"; then
  xcrun simctl boot "$SIM"
fi
xcrun simctl bootstatus "$SIM" -b
BUILD_ACTION=build
[[ $ACTION == test ]] && BUILD_ACTION=test
xcodebuild -project "$ROOT/NeoDizzy.xcodeproj" -scheme NeoDizzy -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$ROOT/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO "$BUILD_ACTION"
if [[ $ACTION == run ]]; then
  APP=$ROOT/DerivedData/Build/Products/Debug-iphonesimulator/NeoDizzy.app
  xcrun simctl install "$SIM" "$APP"
  xcrun simctl launch "$SIM" com.elsterlee.NeoDizzy
  SIMULATOR_APP="$(xcode-select -p)/Applications/Simulator.app"
  if [[ -d $SIMULATOR_APP ]]; then
    open -a "$SIMULATOR_APP"
  else
    echo "App 已启动；可在 Xcode 的模拟器运行界面查看。"
  fi
fi
