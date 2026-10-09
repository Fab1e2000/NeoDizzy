#!/bin/zsh
# 构建 NeoDizzy，并安装、启动到真机。
# 用法：scripts/deploy-device.sh [Debug|Release] [--no-launch]
# 设备从环境变量或仓库根目录的 .env 读取（模板见 .env.example），
# 团队 ID 从 Config/Signing.local.xcconfig 读取。
# 使用 Xcode 自动签名，Bundle ID 与其他 App 互不冲突；小组件的 ID 自动跟着 App 改。
set -euo pipefail

ROOT=${0:A:h:h}
# 显式传入的环境变量优先于 .env。
REQUESTED_DEVICE=${NEODIZZY_DEVICE:-}
REQUESTED_BUNDLE=${NEODIZZY_BUNDLE_ID:-}
[[ -f $ROOT/.env ]] && source $ROOT/.env
[[ -n $REQUESTED_DEVICE ]] && NEODIZZY_DEVICE=$REQUESTED_DEVICE
[[ -n $REQUESTED_BUNDLE ]] && NEODIZZY_BUNDLE_ID=$REQUESTED_BUNDLE

CONFIG=Release
LAUNCH=1
for arg in "$@"; do
  case $arg in
    Debug|Release) CONFIG=$arg ;;
    --no-launch) LAUNCH=0 ;;
    *) echo "未知参数：$arg" >&2; exit 64 ;;
  esac
done

DEVICE=${NEODIZZY_DEVICE:?请在 .env 里设置 NEODIZZY_DEVICE（iPhone 的 UDID）}
if ! grep -qE '^DEVELOPMENT_TEAM *= *[A-Z0-9]+' "$ROOT/Config/Signing.local.xcconfig" 2>/dev/null; then
  echo "请复制 Config/Signing.local.xcconfig.example 为 Signing.local.xcconfig 并填写团队 ID" >&2
  exit 78
fi
BUNDLE_ID=${NEODIZZY_BUNDLE_ID:-com.elsterlee.NeoDizzy}
DERIVED=$ROOT/DerivedData

# 改过 project.yml 后要先重新生成工程；syncedFolder 下新增源文件不需要。
if [[ $ROOT/project.yml -nt $ROOT/NeoDizzy.xcodeproj/project.pbxproj ]]; then
  xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
fi

xcodebuild -project "$ROOT/NeoDizzy.xcodeproj" -scheme NeoDizzy -configuration "$CONFIG" \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Automatic APP_BUNDLE_ID="$BUNDLE_ID" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet

APP=$DERIVED/Build/Products/$CONFIG-iphoneos/NeoDizzy.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
if (( LAUNCH )); then
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
fi
echo "已推送 $BUNDLE_ID（$CONFIG）"
