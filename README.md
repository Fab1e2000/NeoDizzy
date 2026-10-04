<div align="center">

<img src="NeoDizzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" height="128" alt="NeoDizzy 黑金 D 图标">

# NeoDizzy

**为 iPhone 和 Mac 打造的第三方 DizzyLab 音乐客户端**

SwiftUI 原生构建 · 黑金深色界面 · 在线试听与离线音乐

[![Release](https://img.shields.io/github/v/release/Fab1e2000/NeoDizzy?style=flat-square&color=F0AD4E&label=release)](https://github.com/Fab1e2000/NeoDizzy/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Fab1e2000/NeoDizzy/total?style=flat-square&color=F0AD4E)](https://github.com/Fab1e2000/NeoDizzy/releases)
[![CI](https://github.com/Fab1e2000/NeoDizzy/actions/workflows/ci.yml/badge.svg)](https://github.com/Fab1e2000/NeoDizzy/actions/workflows/ci.yml)
[![iOS 27+](https://img.shields.io/badge/iOS-27%2B-111111?style=flat-square&logo=apple&logoColor=white)](#运行要求)
[![macOS 27+](https://img.shields.io/badge/macOS-27%2B-111111?style=flat-square&logo=apple&logoColor=white)](#macos-版)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![GPLv3](https://img.shields.io/badge/license-GPLv3-8A8F98?style=flat-square)](LICENSE)

[下载](#安装) · [功能](#功能亮点) · [macOS 版](#macos-版) · [从源码构建](#从源码构建) · [更新日志](docs/releases) · [反馈问题](https://github.com/Fab1e2000/NeoDizzy/issues)

</div>

<br>

> [!IMPORTANT]
> NeoDizzy 是独立开发的非官方第三方客户端，与 DizzyLab 及其运营方不存在隶属、合作或授权关系。使用前请阅读 [免责声明](DISCLAIMER.md)，并尊重创作者的作品与购买权限。

## 关于 NeoDizzy

NeoDizzy 将 [DizzyLab](https://www.dizzylab.net) 的音乐浏览、试听、已购库和社区内容带到 iPhone 和 Mac。使用原生 SwiftUI 界面，支持后台播放、锁屏控制，以及将已购音乐下载到自己选择的文件夹。界面提供简体中文。

## 功能亮点

### 发现音乐

- **分类浏览**：数字专辑、单曲 EP、下载商品、pack 和限时优惠；支持专辑、社团、标签及用户搜索。
- **随便听听**：独立标签页，点击页面中的按钮后获取随机曲目，自动播放并展开播放器；上一首回听历史，下一首请求新歌曲。
- **社团与关注**：浏览社团作品、关注或取消关注。关注页每个社团只显示一次，点击进入详情查看专辑。

### 播放与音乐库

- **试听与完整版**：未购买的作品按网站提供的试听地址播放，并标明「试听」；登录后可串流自己已购的完整版。
- **后台与锁屏控制**：支持播放、暂停、切歌、进度控制，保存播放队列、模式和进度。
- **迷你播放器**：始终在完整标签栏上方显示，不随页面滚动收缩；点按展开大封面播放页。进入后一秒内禁止退出手势，退出后可直接滚动。
- **已购买与本地库**：独立标签页；已购买保留站点购买记录，本地库汇总下载专辑和第三方音乐。
- **离线播放**：下载已购专辑的 MP3 / FLAC ZIP，解压到下载目录；播放时优先读取本地音频。
- **第三方音乐**：读取系统可播放的 MP3、M4A/AAC/ALAC、FLAC、WAV、AIFF 和 CAF 单曲文件，识别音频标签、多碟曲序与封面；缺少标签时使用目录和文件名。不做联网匹配或 CUE 整轨分曲。
- **作者与歌手**：分别读取内嵌的专辑艺术家和曲目艺术家，保留多人署名。已完全弃用 `.melox.json`：不读取、不迁移，也不删除已有描述文件；升级后自动刷新旧索引。
- **编辑内嵌标签**：在本地库专辑页长按曲目，编辑标题、歌手、专辑名、专辑艺术家、曲号、碟号、年份、流派及主封面。支持 MP3、FLAC、M4A/MP4（AAC/ALAC）、WAV、AIFF，不重新编码音频；裸 AAC、CAF、受保护或损坏文件暂不支持编辑。多人姓名分别填写，不按 `/` 拆分；空白字段删除对应标签。选择的封面转为最大 2048 像素 PNG；原有未修改封面、附加图片和歌词保留。
- **批量编辑 FLAC**：本地专辑页播放按钮右侧的“批量编辑”打开曲目选择和标签表单。默认选中可读取的 FLAC；只有勾选的歌手、专辑名、专辑艺术家、年份、流派或主封面会统一覆盖，勾选后留空表示删除。标题、曲号和碟号保持原值。逐首保存并列出错误，已成功的文件不会重复写入；全部成功并刷新后 0.5 秒关闭。
- **标签保存与播放**：播放器仍持有文件时（包括暂停），先在编辑页点击“停止播放以保存”，再保存；不会自动恢复播放。保存通过副本验证后替换，刷新本地库、队列和播放器信息，文件夹分组与曲目身份保持不变。若文件被其他应用更改，保留草稿并提示重新读取；文件已保存但索引刷新失败时可单独重试刷新。文件提供商必须允许写入，并有足够空间存放副本。
- **多个扫描目录**：我的 → 设置 → 扫描目录，可添加、重新授权或移除文件夹。下载目录自动入库，额外扫描目录可与下载目录不同，本地库下拉即可重新扫描；重叠目录中的同一文件只收录一次。
- **下载文件改名**：重新扫描时按明确的曲号或曲名恢复关联；无法唯一匹配时按当前音频作为本地专辑读取，不修改原始清单。
- **本地歌词**：播放器左下角打开歌词。优先使用手动导入的 LRC / TXT，其次是音频同目录同名 LRC，最后读取音频内嵌歌词。支持 UTF-8 / UTF-16、逐行同步、点击跳转和纯文本；手动滚动后自动恢复跟随。「我的 → 设置 → 歌词」可调整高亮位置，默认居中。导入文件只存到 App 内，不改动音乐文件。
- **按文件夹分专辑**：每个直接包含音频的文件夹是一张专辑，名称取文件夹名；内部曲目的专辑名和艺术家标签不再拆分专辑。递归扫描子目录，CD / Disc 子目录也各自成专辑，不跨目录合并或隐藏重复副本。下载清单只补充曲目信息，不额外生成专辑卡片。
- **只读索引**：第三方目录不会写入清单或改动音频，索引与封面缓存保存在 App 内。移除扫描来源不会删除音乐；更换下载目录后旧目录保留为额外扫描来源。

### 购买与社区

- **数字专辑购买与 BOOST**：原生价格、追加支持及附言面板，通过支付宝收银台付款；返回 App 后按当前账号核验到账。
- **待核验记录**：按账号保存在本机，重启后可继续核验；停止跟踪不会取消订单或退款。
- **社区互动**：专辑 +dB、短评发表和删除、repo 长评及图片阅读、用户主页；repo 回复仍由网页提供。

### 我的与浏览记录

- **专辑浏览记录**：仅记录进入专辑详情页，按最近访问排序并去重；点击重访，支持左滑删除和清空。
- **本机保存**：保留最近 200 张专辑，重启后仍可查看；不记录搜索、社团或用户页面的访问。
- **启动页面**：我的 → 设置 → 启动页面，可选择每次启动显示的页面；该页面被隐藏时改为第一个可见普通页面，不更改隐藏配置。
- **专辑导航**：采用普通导航推入、系统返回按钮及 MeloX 的独立封面背景容器；列表提前加载详情封面和模糊背景。
- **标题栏设置**：可选择固定在顶部，或随页面内容滚动。
- **标签栏设置**：我的 → 设置 → 标签栏，可拖动排序、隐藏页面或恢复默认；至少保留一个页面。默认显示发现、随便听听、社团、关注、已购买、本地库六个页面；超出系统标签栏容量的页面由系统收纳。搜索框位于发现页顶部。

## macOS 版

原生 SwiftUI 的 Mac 版，功能与 iOS 版对齐，界面参考 macOS 的「音乐」App，与 iOS 版一致固定深色界面，强调色为 DizzyLab 金色。

- **窗口布局**：不使用侧边栏，工具栏正中是一组分段按钮作为顶部导航（搜索、发现、随便听听、社团、关注、已购买、本地库、最近浏览）；窗口变窄时只显示图标，再次点击当前项回到该页的第一页。导航项可在设置中显示、隐藏和排序。
- **搜索**：独立页面，标题下方是搜索框，回车后依次显示社团、用户与作品；没有搜索时列出最近搜索的关键词，点击即可重新搜索。
- **播放条与面板**：窗口底部是贴边的三栏播放条（左侧封面与曲目信息，中间播放控制与进度，右侧歌词、待播清单、AirPlay 和音量），窗口变窄时依次收起随机 / 循环和音量滑块。右侧面板显示逐行歌词或待播清单，可拖动分隔线调整宽度；窗口太窄时先自动加宽再展开面板。
- **键盘与菜单**：空格键播放 / 暂停（输入文字时不受影响），⌘← / ⌘→ 切歌，⌘↑ / ⌘↓ 调音量，⌘L 前往当前歌曲，⌘F 搜索，⌘R 刷新当前页面，⌘O 添加音乐文件夹，⌥⌘L / ⌥⌘U 打开歌词 / 待播清单面板；键盘媒体键与控制中心「正在播放」同样可用。
- **专辑页**：页头参考「音乐」，标题按长度调整字号，多位艺术家时只列前三位；曲目列表悬停高亮，双击或回车播放，右键菜单编辑本地曲目标签；底部显示同一社团的更多作品。网格中悬停封面可直接播放，并提前加载专辑详情。本地库可切换为可排序的歌曲表格。
- **下载**：已购专辑在专辑页直接下载并显示进度，下载目录在设置中修改。
- **设置**（⌘,）：启动页面、导航栏、歌词高亮位置、下载目录与扫描目录、账户。
- **沙盒与文件夹授权**：Mac 版运行在 App 沙盒中，只访问你在系统面板中选择的文件夹，并保存为带安全范围的书签，重启后无需重新授权。
- **购买**：Mac 上没有支付宝 App，收银台在 App 内打开网页版，用手机支付宝扫码或登录支付宝账户付款，完成后自动核验到账。

## 运行要求

- iPhone，**iOS 27.0 或更高版本**；当前为竖屏界面。
- Mac，**macOS 27.0 或更高版本**。
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

macOS 版为 ad-hoc 签名的磁盘映像 `NeoDizzy-macOS-vX.Y.Z.dmg`（与 IPA 共用 `SHA256SUMS.txt`）。打开后将 NeoDizzy 拖到旁边的「应用程序」；首次打开时若系统提示无法验证开发者，在「系统设置 → 隐私与安全性」中选择「仍要打开」。

## 离线音乐的使用

从已购专辑详情进入下载，在下载面板选择保存文件夹，选择网站提供的音频格式。文件保存到所选目录下的社团 / 专辑文件夹，附带 `.neodizzy.json` 曲目对应关系。

重复下载同一专辑会在完整导入后覆盖旧版本，并保留单独下载的特典；下载或导入失败不会删除旧版本。下载完成后，可在断网或退出账号时播放本地音乐。在「文件」App 中移动或删除音频后，需要回本地库重新扫描。重新扫描会刷新文件元数据；支持下载目录和额外添加的第三方音乐目录。云盘中没有保留本地副本的文件不保证离线可用。

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

## 本机开发工作流

首次 clone 后执行 `scripts/setup.sh`：检查工具、创建未入库的本机配置、生成工程，并按 `Package.resolved` 解析依赖。重复执行不会覆盖已有 `.env` 或签名配置。

```sh
scripts/setup.sh
scripts/simulator.sh run    # 构建、安装并启动 iOS 27 iPhone 模拟器
scripts/simulator.sh test   # 完整 iOS 测试
scripts/mac.sh run          # 构建并启动 macOS 版（ad-hoc 签名）
scripts/mac.sh package      # 打包 macOS 版 dmg 到 dist/
python3 scripts/test-core.py
scripts/deploy-device.sh Debug
```

Mac 版使用 `NeoDizzyMac` Scheme 和独立的 `com.elsterlee.NeoDizzyMac` Bundle ID。脚本使用 ad-hoc 签名，每次重新构建后钥匙串可能再次询问是否允许读取登录会话；在 Xcode 中选择开发团队运行可避免。`NeoDizzyMac` target 与 iOS 共用 `NeoDizzy/` 目录，通过 `project.yml` 的 `excludes` 排除 iOS 专属的 `App/`、`Features/` 等文件；新增或移动 iOS 专属文件后需运行 `xcodegen generate`，否则它会被一并编译进 Mac 版。

可通过 `NEODIZZY_SIMULATOR=<UDID>` 指定模拟器。真机设备填入 `.env` 的 `NEODIZZY_DEVICE`；显式环境变量优先于文件配置。Xcode 选择 NeoDizzy Scheme 后，使用 `⌘R` 运行和调试、`⌘U` 测试、`⌘I` 性能分析。

真机使用独立的 `com.elsterlee.NeoDizzy` Bundle ID。需要在 Xcode 登录有权限的开发账号并启用自动签名，或准备匹配该 Bundle ID 的开发描述文件。其他 App 的固定 App ID 描述文件不能用于此应用；改为相同 Bundle ID 安装会覆盖原应用。

## 测试与 CI

```sh
python3 scripts/test-core.py
```

核心回归测试在 macOS 上直接运行，覆盖解析、账号网络、下载解压、离线目录、购买核验、社区、分页与浏览记录。完整 iOS 测试可在 Xcode 的 Test 操作中运行。

GitHub Actions 在推送和 PR 时自动安装所需 Metal 工具链，执行核心测试与 iOS 模拟器测试，并构建设备版 IPA 和 macOS 版 dmg。推送 `v*` 标签时，测试和构建通过后自动发布 Release，附带 IPA、macOS dmg 与 SHA-256 校验文件。iOS 与 macOS 的版本号都必须与标签一致（`project.yml` 中两个 target 的 `CFBundleShortVersionString`），并提供对应的 `docs/releases/vX.Y.Z.md`。

## 项目结构

```text
NeoDizzy/
├── App/                 # iOS 入口与标签栏
├── Shared/              # iOS 与 macOS 共用：服务容器、导航、页面状态、歌词视图与收银台导航
├── Core/
│   ├── Account/         # 登录与本机会话
│   ├── BrowsingHistory/ # 专辑浏览记录
│   ├── Community/      # 社区接口与解析
│   ├── Downloads/      # 下载任务与 ZIP 解压
│   ├── OfflineLibrary/ # 文件夹授权、扫描与音轨索引
│   ├── Playback/       # 播放队列、恢复及系统媒体控制
│   ├── Purchases/      # 购买、收银台导航与到账核验
│   └── …               # Models、Networking、UI
├── Features/            # iOS 页面：发现、社团、关注、音乐库、播放页与我的
└── Resources/           # 图标与界面资源（两个平台共用）
NeoDizzyMac/
├── App/                 # macOS 入口、窗口、顶部导航、菜单命令与空格键
├── Components/          # 专辑网格、曲目列表、页头与加载状态
└── Features/            # 各页面、播放条、歌词 / 待播清单面板、设置
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
- 歌词仅读取本地来源，不联网匹配；当前不提供均衡器、AutoMix、灵动岛或 Apple Watch 功能。

## 参与项目

欢迎通过 [Issues](https://github.com/Fab1e2000/NeoDizzy/issues) 反馈问题。请说明系统版本、App 版本和复现步骤，避免上传登录凭据、付款链接或其他私人信息。提交 PR 前请确认工程可构建，并通过核心回归测试。

## 许可证与致谢

NeoDizzy 以 [GNU GPLv3](LICENSE) 发布。此许可证不授予任何 DizzyLab 内容、商标或服务的权利；音乐和社区内容的版权归各自权利人所有。请支持创作者，购买和下载的作品仅供个人使用，不要重新上传或公开分发。

- [MeloX](https://github.com/youshen2/MeloX) / MeloX_Modified：播放队列、系统媒体控制、播放器界面与标题栏逻辑的来源或参考。专辑页容器、背景预模糊与预加载方式移植自 v1.2.1（GPL-3.0），适配本地专辑及 DizzyLab 数据。
- [NeoBili](https://github.com/Fab1e2000/NeoBili)：界面组织、立体字母图标和本 README 的排版参考。
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)：HTML 解析。
- [Nuke](https://github.com/kean/Nuke)：封面加载与缓存。
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)：ZIP 解压。

具体来源与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
