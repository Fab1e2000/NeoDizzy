# NeoDizzy 本机工作流验证（2026-09-30）

- Xcode 27.0（27A266a），XcodeGen 可用。
- 已安装 Metal Toolchain 27A266a。
- 已按 Package.resolved 解析 SwiftSoup 2.13.9、Nuke 13.2.0、ZIPFoundation 0.9.20。
- 核心回归：160 个测试、22 个测试组通过。
- 完整 iOS 模拟器测试：247 个测试通过，0 失败、0 跳过（详见 test-summary.json）。
- iPhone 18 Pro / iOS 27 模拟器安装并启动成功，发现页已截图验证。
- Release iOS 设备架构构建及未签名 IPA 打包成功：dist/NeoDizzy-v0.2.0-unsigned.ipa。
- 真机设备与团队已写入被 Git 忽略的 .env、Config/Signing.local.xcconfig。

## 真机签名与部署完成

Xcode 已登录 Personal Team D6647H7B4X；已改用该团队自动生成 com.elsterlee.NeoDizzy 的开发描述文件。
Debug 真机签名构建、安装并启动成功，未替换 NeoBili。详见 device-deploy.log。
Personal Team 描述文件有效期为 7 天，到期后重新运行部署脚本续签。
LLDB 暂停及性能分析未单独验证。

## 日常入口

```sh
scripts/setup.sh
scripts/simulator.sh run
scripts/simulator.sh test
python3 scripts/test-core.py
scripts/deploy-device.sh Debug
scripts/package-unsigned.sh
```
