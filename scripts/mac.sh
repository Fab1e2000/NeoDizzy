#!/bin/zsh
# 用法：scripts/mac.sh [run|build|package]
#   run      构建 Debug 并启动 macOS 版
#   build    只构建 Debug
#   package  构建 Release，ad-hoc 签名后打包为 dmg（含「应用程序」快捷方式），并更新 dist/SHA256SUMS.txt
# 脚本统一使用 ad-hoc 签名，不需要开发者账号；需要固定签名（例如钥匙串不再重复询问）时，在 Xcode 中选择开发团队运行。
set -euo pipefail
ROOT=${0:A:h:h}
ACTION=${1:-run}
[[ $ACTION == run || $ACTION == build || $ACTION == package ]] || { echo "用法：$0 [run|build|package]" >&2; exit 64; }
cd "$ROOT"
ADHOC=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

if [[ $ACTION == package ]]; then
  version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' NeoDizzyMac/Info.plist)
  if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$version" ]]; then
    echo "版本标签与 NeoDizzyMac/Info.plist 不一致" >&2
    exit 1
  fi
  xcodebuild -project NeoDizzy.xcodeproj -scheme NeoDizzyMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/mac \
    -onlyUsePackageVersionsFromResolvedFile "${ADHOC[@]}" build -quiet
  app=build/mac/Build/Products/Release/NeoDizzy.app
  codesign --verify --strict "$app"
  mkdir -p dist
  output="$PWD/dist/NeoDizzy-macOS-v$version.dmg"
  rm -f "$output"
  # 磁盘映像里放 App 和「应用程序」快捷方式，打开后拖进去即可安装。
  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT
  ditto "$app" "$stage/NeoDizzy.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "NeoDizzy $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$output" -quiet
  hdiutil verify "$output" -quiet
  # 与 iOS 的 IPA 共用一份校验文件。
  (cd dist && shasum -a 256 *.ipa(N) *.dmg(N) > SHA256SUMS.txt)
  echo "$output"
  exit 0
fi

xcodebuild -project NeoDizzy.xcodeproj -scheme NeoDizzyMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$ROOT/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile "${ADHOC[@]}" build -quiet
if [[ $ACTION == run ]]; then
  # 只结束上一次构建的 Mac 版，不影响模拟器里同名的 iOS 进程。
  pkill -f "/Build/Products/Debug/NeoDizzy.app/Contents/MacOS/NeoDizzy" 2>/dev/null || true
  open "$ROOT/DerivedData/Build/Products/Debug/NeoDizzy.app"
fi
