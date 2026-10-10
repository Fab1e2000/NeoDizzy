#!/bin/zsh
# 用外部开发证书（.p12 + .mobileprovision）重签 NeoDizzy 的 ipa，并安装到真机。
# Bundle ID 改成描述文件绑定的 App ID，让 application-identifier 与 Bundle ID 一致，
# 否则文件选择器选中的目录会被系统拒绝（选完“打开”没有反应）。
#
# 用法：scripts/resign-ipa.sh <ipa> <p12> <mobileprovision> [--no-install]
# 只在终端提示时输入一次证书密码；密码不会写入任何文件。
set -euo pipefail

IPA=${1:?用法：scripts/resign-ipa.sh <ipa> <p12> <mobileprovision> [--no-install]}
P12=${2:?缺少 .p12}
PROFILE=${3:?缺少 .mobileprovision}
INSTALL=1
[[ ${4:-} == --no-install ]] && INSTALL=0
IPA=${IPA:A} P12=${P12:A} PROFILE=${PROFILE:A}

ROOT=${0:A:h:h}
[[ -f $ROOT/.env ]] && source $ROOT/.env
OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
[[ -x $OPENSSL ]] || { echo "需要 Homebrew 的 openssl@3：brew install openssl@3" >&2; exit 69; }

WORK=$(mktemp -d -t neodizzy-resign)
KEYCHAIN=$WORK/signing.keychain-db
KEYCHAIN_PASSWORD=$(uuidgen)
ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | tr -d ' "')}")
cleanup() {
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 描述文件：App ID、团队 ID
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
APP_ID=$(plutil -extract Entitlements.application-identifier raw "$WORK/profile.plist")
TEAM=$(plutil -extract 'TeamIdentifier.0' raw "$WORK/profile.plist")
BUNDLE_ID=${APP_ID#$TEAM.}
WILDCARD=0
if [[ $BUNDLE_ID == *'*'* ]]; then WILDCARD=1; BUNDLE_ID=com.elsterlee.NeoDizzy; APP_ID=$TEAM.$BUNDLE_ID; fi
GET_TASK_ALLOW=$(plutil -extract Entitlements.get-task-allow raw "$WORK/profile.plist" 2>/dev/null || echo false)
echo "描述文件：$(plutil -extract Name raw "$WORK/profile.plist")，到期 $(plutil -extract ExpirationDate raw "$WORK/profile.plist")"
echo "Bundle ID 将设为 $BUNDLE_ID"

# 证书：OpenSSL 3 导出的 .p12 钥匙串读不了，先转成旧格式再导入临时钥匙串。
read -rs "P12_PASSWORD?请输入证书密码："; echo
export P12_PASSWORD
$OPENSSL pkcs12 -in "$P12" -nodes -passin env:P12_PASSWORD -out "$WORK/identity.pem" \
  || { echo "证书密码不对" >&2; exit 1; }
$OPENSSL pkcs12 -export -legacy -in "$WORK/identity.pem" -out "$WORK/identity.p12" -passout env:P12_PASSWORD
rm -f "$WORK/identity.pem"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
unset P12_PASSWORD
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1{print $2}')
[[ -n $IDENTITY ]] || { echo "证书里没有可用于签名的身份" >&2; exit 1; }

# 重签
cd "$WORK"
unzip -q "$IPA"
APP=$(print -l Payload/*.app(N) | head -1)
[[ -n $APP ]] || { echo "ipa 里没有 .app" >&2; exit 1; }
ORIGINAL_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"
cat > entitlements.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$APP_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>get-task-allow</key><$GET_TASK_ALLOW/>
  <key>keychain-access-groups</key><array><string>$APP_ID</string></array>
</dict></plist>
PLIST
for nested in "$APP"/Frameworks/*(N); do
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" "$nested"
done
# 小组件扩展的 Bundle ID 必须以 App 的 Bundle ID 开头，并由描述文件覆盖。
# 通配描述文件可以一起签；只绑定一个 App ID 的描述文件签不了，只能去掉小组件，否则系统拒绝安装。
for appex in "$APP"/PlugIns/*.appex(N); do
  if (( WILDCARD )); then
    APPEX_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$appex/Info.plist")
    APPEX_ID=$BUNDLE_ID${APPEX_ID#$ORIGINAL_ID}
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APPEX_ID" "$appex/Info.plist"
    cp "$PROFILE" "$appex/embedded.mobileprovision"
    rm -rf "$appex/_CodeSignature"
    sed "s/$APP_ID/$TEAM.$APPEX_ID/g" entitlements.plist > appex-entitlements.plist
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --entitlements appex-entitlements.plist "$appex"
  else
    echo "描述文件只覆盖 $BUNDLE_ID，已移除 ${appex:t}（「正在播放」小组件不可用）"
    rm -rf "$appex"
  fi
done
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --entitlements entitlements.plist "$APP"
codesign --verify --strict "$APP"

OUT=${IPA:r}-$BUNDLE_ID.ipa
rm -f "$OUT"
zip -qry "$OUT" Payload
echo "已签名：$OUT"

if (( INSTALL )); then
  DEVICE=${NEODIZZY_DEVICE:?请在 .env 里设置 NEODIZZY_DEVICE（iPhone 的 UDID）}
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "已安装 $BUNDLE_ID"
fi
