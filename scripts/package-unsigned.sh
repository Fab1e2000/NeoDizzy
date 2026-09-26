#!/bin/bash
# 构建供侧载工具重新签名的设备 IPA；不包含开发者证书。
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' NeoDizzy/Info.plist)
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$version" ]]; then
  echo "版本标签与 Info.plist 不一致" >&2
  exit 1
fi
xcodebuild -project NeoDizzy.xcodeproj -scheme NeoDizzy -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/unsigned \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build -quiet
app=build/unsigned/Build/Products/Release-iphoneos/NeoDizzy.app
[[ -x "$app/NeoDizzy" ]]
mkdir -p dist
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/NeoDizzy.app"
output="$PWD/dist/NeoDizzy-v$version-unsigned.ipa"
# ditto creates a fresh archive instead of retaining entries from an older build.
ditto -c -k --norsrc --keepParent "$stage/Payload" "$output"
(cd dist && shasum -a 256 "NeoDizzy-v$version-unsigned.ipa" > SHA256SUMS.txt)
echo "$output"
