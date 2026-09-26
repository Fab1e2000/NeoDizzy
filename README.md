<div align="center">

<img src="NeoDizzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" height="128" alt="NeoDizzy 黑金 D 图标">

# NeoDizzy

**为 iPhone 打造的第三方 DizzyLab 音乐客户端**

SwiftUI 原生构建 · 黑金深色界面 · 在线试听与离线音乐

[![Release](https://img.shields.io/github/v/release/Fab1e2000/NeoDizzy?style=flat-square&color=F0AD4E&label=release)](https://github.com/Fab1e2000/NeoDizzy/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Fab1e2000/NeoDizzy/total?style=flat-square&color=F0AD4E)](https://github.com/Fab1e2000/NeoDizzy/releases)
[![CI](https://github.com/Fab1e2000/NeoDizzy/actions/workflows/ci.yml/badge.svg)](https://github.com/Fab1e2000/NeoDizzy/actions/workflows/ci.yml)
[![iOS 27+](https://img.shields.io/badge/iOS-27%2B-111111?style=flat-square&logo=apple&logoColor=white)](#运行要求)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![GPLv3](https://img.shields.io/badge/license-GPLv3-8A8F98?style=flat-square)](LICENSE)

[下载](#安装) · [功能](#功能亮点) · [从源码构建](#从源码构建) · [更新日志](docs/releases) · [反馈问题](https://github.com/Fab1e2000/NeoDizzy/issues)

</div>

<br>

> [!IMPORTANT]
> NeoDizzy 是独立开发的非官方第三方客户端，与 DizzyLab 及其运营方不存在隶属、合作或授权关系。使用前请阅读 [免责声明](DISCLAIMER.md)，并尊重创作者的作品与购买权限。

## 关于 NeoDizzy

NeoDizzy 将 [DizzyLab](https://www.dizzylab.net) 的音乐浏览、试听、已购库和社区内容带到 iPhone。使用原生 SwiftUI 界面，支持后台播放、锁屏控制，以及将已购音乐下载到自己选择的文件夹。界面提供简体中文。

## 功能亮点

### 发现音乐

- **分类浏览**：数字专辑、单曲 EP、下载商品、pack 和限时优惠；支持专辑、社团、标签及用户搜索。
- **随便听听**：点击后获取随机曲目，自动播放并展开播放器；上一首回听历史，下一首请求新歌曲。
- **社团与关注**：浏览社团作品、关注或取消关注。关注页每个社团只显示一次，点击进入详情查看专辑。

### 播放与音乐库

- **试听与完整版**：未购买的作品按网站提供的试听地址播放，并标明「试听」；登录后可串流自己已购的完整版。
- **后台与锁屏控制**：支持播放、暂停、切歌、进度控制，保存播放队列、模式和进度。
- **迷你播放器**：在标签栏上方显示，随标签栏收缩；点按展开大封面播放页。
- **离线播放**：下载已购专辑的 MP3 / FLAC ZIP，解压到所选文件夹；播放时优先读取本地音频。

### 购买与社区

- **数字专辑购买与 BOOST**：原生价格、追加支持及附言面板，通过支付宝收银台付款；返回 App 后按当前账号核验到账。
- **待核验记录**：按账号保存在本机，重启后可继续核验；停止跟踪不会取消订单或退款。
- **社区互动**：专辑 +dB、短评发表和删除、repo 长评及图片阅读、用户主页；repo 回复仍由网页提供。

### 我的与浏览记录

- **专辑浏览记录**：仅记录进入专辑详情页，按最近访问排序并去重；点击重访，支持左滑删除和清空。
- **本机保存**：保留最近 200 张专辑，重启后仍可查看；不记录搜索、社团或用户页面的访问。
- **标题栏设置**：可选择固定在顶部，或随页面内容滚动。

## 运行要求

- iPhone，**iOS 27.0 或更高版本**；当前为竖屏界面。
- 构建需要 **Xcode 27**；工程使用 Swift 5 语言模式。
- 真机安装需要自己的签名证书或可用于签名的 Apple 开发账号。

## 安装

NeoDizzy 通过 **未签名 IPA** 分发，需要自行签名后安装。

1. 从 [最新 Release](https://github.com/Fab1e2000/NeoDizzy/releases/latest) 下载 `NeoDizzy-vX.Y.Z-unsigned.ipa` 和 `SHA256SUMS.txt`。
2. 将两个文件放在同一目录，校验下载完整性：
   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```
3. 使用自己的证书或侧载工具重新签名，将 IPA 安装到 iPhone。

发布包不包含开发者的证书或描述文件，也不能直接点击安装。

## 离线音乐的使用

在「音乐库 → 已下载」选择保存文件夹，再从已购专辑详情进入下载，选择网站提供的音频格式。文件保存到所选目录下的社团 / 专辑文件夹，附带 `.neodizzy.json` 曲目对应关系。

下载完成后，可在断网或退出账号时播放本地音乐。在「文件」App 中移动或删除音频后，需要回音乐库重新扫描。扫描仅识别 NeoDizzy 生成的专辑目录，目前不支持任意本地音乐文件夹导入。云盘中没有保留本地副本的文件不保证离线可用。

## 从源码构建

安装 Xcode 27；修改工程配置时另需 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
git clone https://github.com/Fab1e2000/NeoDizzy.git
cd NeoDizzy
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
open NeoDizzy.xcodeproj
```

1. 在 `Config/Signing.local.xcconfig` 中填写自己的开发团队 ID；该文件不会提交到 Git。
2. 等待 Swift Package Manager 解析 SwiftSoup、Nuke 和 ZIPFoundation。
3. 选择 `NeoDizzy` Scheme 和 iPhone，构建运行；如有需要，修改 Bundle Identifier。

通过脚本安装到已连接的手机：

```sh
cp .env.example .env       # 填写设备 UDID
scripts/deploy-device.sh Release
```

生成未签名 IPA 和校验文件：

```sh
scripts/package-unsigned.sh
# 输出到 dist/
```

工程配置由 `project.yml` 管理，修改后运行 `xcodegen generate`。源代码目录使用 Xcode 同步文件夹，新增 Swift 文件无需重新生成工程。

## 测试与 CI

```sh
python3 scripts/test-core.py
```

核心回归测试在 macOS 上直接运行，覆盖解析、账号网络、下载解压、离线目录、购买核验、社区、分页与浏览记录。完整 iOS 测试可在 Xcode 的 Test 操作中运行。

GitHub Actions 在推送和 PR 时自动安装所需 Metal 工具链，执行核心测试与 iOS 模拟器测试，并构建设备版 IPA。推送 `v*` 标签时，测试和构建通过后自动发布 Release，附带 IPA 与 SHA-256 校验文件。版本号必须与 Info.plist 一致，并提供对应的 `docs/releases/vX.Y.Z.md`。

## 项目结构

```text
NeoDizzy/
├── App/                 # App 入口、共享服务、标签栏与导航
├── Core/
│   ├── Account/         # 登录与本机会话
│   ├── BrowsingHistory/ # 专辑浏览记录
│   ├── Community/      # 社区接口与解析
│   ├── Downloads/      # 下载任务与 ZIP 解压
│   ├── OfflineLibrary/ # 文件夹授权、扫描与音轨索引
│   ├── Playback/       # 播放队列、恢复及系统媒体控制
│   ├── Purchases/      # 购买、收银台导航与到账核验
│   └── …               # Models、Networking、UI
├── Features/            # 发现、社团、关注、音乐库、播放页与我的
└── Resources/           # 图标与界面资源
NeoDizzyTests/           # 测试与脱敏 / 人工构造的样本
scripts/                 # 真机部署、打包、测试与图标生成
design/                  # 可编辑的图标矢量源文件
docs/                    # 规划、接口记录与发布说明
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [更新日志](docs/releases) | 各版本改动与安装说明 |
| [项目规划](docs/PLAN.md) | 阶段目标、实现及验收记录 |
| [网站接口](docs/SITE_API.md) | 已使用的接口与解析约定 |
| [第三方声明](THIRD_PARTY_NOTICES.md) | 依赖和参考项目的来源、许可证 |
| [免责声明](DISCLAIMER.md) | 与平台的关系、内容权利及使用责任 |

## 已知限制

- DizzyLab 网站接口并无兼容性保证，网站改版可能影响解析和部分功能。
- 完整版串流和下载依赖账号的实际购买权限；随机曲目可能是试听片段。
- pack 整包购买、PayPal、购物车、兑换码、实体商品，以及注册和找回密码仍使用网站。
- repo 目前支持原生阅读，未提供原生长评编辑与回复。
- 未识别的支付宝回跳格式可能需要手动返回 App；付款结果以服务端订单核验为准。
- 后台下载唤醒、网络中断和文件夹授权失效等异常场景仍需持续真机验证。
- 当前不提供歌词、均衡器、AutoMix、灵动岛或 Apple Watch 功能。

## 参与项目

欢迎通过 [Issues](https://github.com/Fab1e2000/NeoDizzy/issues) 反馈问题。请说明系统版本、App 版本和复现步骤，避免上传登录凭据、付款链接或其他私人信息。提交 PR 前请确认工程可构建，并通过核心回归测试。

## 许可证与致谢

NeoDizzy 以 [GNU GPLv3](LICENSE) 发布。此许可证不授予任何 DizzyLab 内容、商标或服务的权利；音乐和社区内容的版权归各自权利人所有。请支持创作者，购买和下载的作品仅供个人使用，不要重新上传或公开分发。

- [MeloX](https://github.com/youshen2/MeloX) / MeloX_Modified：播放队列、系统媒体控制、播放器界面与标题栏逻辑的来源或参考。
- [NeoBili](https://github.com/Fab1e2000/NeoBili)：界面组织、立体字母图标和本 README 的排版参考。
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)：HTML 解析。
- [Nuke](https://github.com/kean/Nuke)：封面加载与缓存。
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)：ZIP 解压。

具体来源与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
