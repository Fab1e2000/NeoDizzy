#!/bin/zsh
# 初始化本机配置，不覆盖已有文件。
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
xcodebuild -version
# Nuke 的 Metal 源文件依赖 Xcode 可选组件；已安装时此操作直接返回。
xcodebuild -downloadComponent MetalToolchain
command -v xcodegen >/dev/null || { echo "请先安装 XcodeGen：brew install xcodegen" >&2; exit 69; }
[[ -f Config/Signing.local.xcconfig ]] || cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
[[ -f .env ]] || cp .env.example .env
xcodegen generate
xcodebuild -resolvePackageDependencies -project NeoDizzy.xcodeproj -scheme NeoDizzy -derivedDataPath "$ROOT/DerivedData" -onlyUsePackageVersionsFromResolvedFile
