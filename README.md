# NeoDizzy

非官方的 [DizzyLab](https://www.dizzylab.net) iOS 第三方客户端，使用原生 SwiftUI 构建。

> NeoDizzy 与 DizzyLab 及其运营方不存在隶属、合作或授权关系。详见 [免责声明](DISCLAIMER.md)。

*An unofficial, open-source SwiftUI client for the DizzyLab doujin music store. Not affiliated with DizzyLab.*

## 下载与自动构建

[下载 Release 0.1.0](https://github.com/Fab1e2000/NeoDizzy/releases/tag/v0.1.0) · [CI 状态](https://github.com/Fab1e2000/NeoDizzy/actions/workflows/ci.yml)

Release 附带未签名 IPA，需要 iOS 27，并使用自己的证书通过侧载工具重新签名。每次推送和 PR 自动运行核心测试、iOS 测试目标编译检查及设备构建；`v*` 标签在测试通过后发布对应 Release。发布前请同步 `project.yml` 与 Info.plist 版本，并准备 `docs/releases/v版本.md`。本地运行 `scripts/package-unsigned.sh` 可生成相同格式的 IPA 和 SHA-256 校验文件。

图标参考 NeoBili 的立体字母样式，使用黑底金色 D；矢量源文件为 [design/AppIcon.svg](design/AppIcon.svg)，运行 `xcrun swift scripts/generate-app-icon.swift` 可重新生成资源。

## 当前状态

目前可以浏览专辑、社团、标签和 pack，可以搜索和试听；登录 DizzyLab 账号后可以收听已购专辑的完整版，查看已购专辑和关注社团的新作。支持后台播放、锁屏控制、已购专辑下载、文件夹授权和离线播放。M4 已接入原生价格与 BOOST 面板、支付宝收银台和付款核验，真实付款链路待真机验收。M5 已接入社区互动、repo 阅读、用户主页和随机发现。界面只提供简体中文。

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M0 骨架 | 工程、深色主题、标签页框架、真机部署脚本 | 已完成 |
| M1 浏览 | 专辑列表与详情、限时优惠、pack、社团、标签、搜索、试听播放 | 已完成 |
| M2 账号 | 登录、已购库、完整版串流、关注动态 | 已完成 |
| M3 离线 | 下载到你选的文件夹，在 App 内离线播放 | 已实现，待真机验收 |
| M4 购买 | 自定价格 / BOOST，支付宝付款 | 已实现，待付款验收 |
| M5 社区 | 点赞、短评、repo、随便听听、用户主页、支持者排行榜、关注社团 | 已实现，待真机验收 |

完整规划见 [docs/PLAN.md](docs/PLAN.md)，网站接口梳理见 [docs/SITE_API.md](docs/SITE_API.md)。

### 离线音乐

在「音乐库 → 已下载」选择保存音乐的文件夹，再到已购专辑详情点「下载」，选择网站提供的 MP3 或 FLAC 格式。下载队列支持查看进度、取消与重试。下载完成后会解压到所选文件夹下的「社团/专辑」目录，并保存 `.neodizzy.json` 曲目对应关系。

已下载专辑无需登录即可进入和播放；播放队列也会优先读取本地文件。在「文件」App 中移动或删除音乐后，回音乐库重新扫描。扫描只识别带 `.neodizzy.json` 的 NeoDizzy 专辑目录，普通音频文件夹不会自动加入。下载文件夹应保存在设备上；云盘中被移除本地副本的文件不能保证断网可用。

已在 iPhone 上验证真实已购 FLAC ZIP 下载、所选文件夹导入及本地音频读取；系统后台唤醒等场景仍待验收，详见规划中的 M3 验收记录。

### 购买与 BOOST

在专辑详情选择「购买 / 支持创作者」或「BOOST · 追加支持」，读取网站最新价格后填写金额和附言。金额支持两位小数和 +1 / +5 / +10 / +50 快捷增加；不能低于网站最低价。已购状态按当前登录账号重新核实，离线文件不会作为购买权限。

点击付款后打开支付宝收银台，返回 App 或点「我已付款」即可核验。普通购买确认专辑权限；BOOST 核对新增的已付订单。核验完成后刷新已购库、下载入口及完整版播放。未确认的记录可在音乐库继续核验，关闭面板和重启不会丢失；每个账号分别保存。核验失败不会标为付款成功，停止跟踪也不等于取消订单或退款。

当前范围是数字专辑、免费领取及已购 BOOST；pack、购物车、实体商品、PayPal 和兑换码仍使用网站。开发验证没有创建真实订单或付款，支付宝 App 跳转和实际到账请在真机验收。

已使用真实已付款 BOOST 验证到账核验。已识别的支付宝调起格式会带上返回 NeoDizzy 的地址；遇到未知的网页收银台格式，付款后可能仍需手动回到 App，系统会继续核验。

## 构建

最低要求 **Xcode 27**、**iOS 27** 设备，另需 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig   # 填写你的开发团队 ID
xcodegen generate          # 根据 project.yml 生成 NeoDizzy.xcodeproj
open NeoDizzy.xcodeproj
```

`Config/Signing.local.xcconfig` 不入库，团队 ID 只保存在你本机。`NeoDizzy/` 是 Xcode 的同步文件夹，新增的 `.swift` 文件会自动参与编译；只有改了 `project.yml` 才需要重新生成工程。

### 推送到真机

```sh
cp .env.example .env       # 填写 iPhone 的 UDID
scripts/deploy-device.sh   # 默认 Release；加 Debug 或 --no-launch 可调整
```

脚本使用 Xcode 自动签名，Bundle ID 默认为 `com.elsterlee.NeoDizzy`，可在 `.env` 里用 `NEODIZZY_BUNDLE_ID` 改成你自己的。

### 核心测试

```sh
python3 scripts/test-core.py
```

可在没有 iOS 模拟器的 Mac 上运行解析、账号网络、离线目录、ZIP、购买金额与到账核验、收银台导航策略和播放队列测试。脚本在临时 Swift Package 中编译实际核心源文件，沿用工程锁定的依赖版本与并发设置。UI、真实支付、后台下载唤醒、文件夹授权和 AVPlayer 播放仍需要 iOS 设备或模拟器验收。

## 许可证与致谢

NeoDizzy 以 [GPLv3](LICENSE) 发布。播放相关代码将移植自同样以 GPLv3 发布的 [MeloX](https://github.com/youshen2/MeloX)，界面组织参考了 NeoBili。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

请支持并尊重创作者：在 DizzyLab 购买后下载的作品仅供个人使用，不要上传发布到任何公开的网络空间。

### M5 社区入口

- 发现页顶部：随便听听、支持者榜。随机发现可换曲，点「播放这首」进入随便听听播放模式：播放器上一首直接回听历史，下一首请求新曲目。历史与模式随播放状态保存；第一首没有历史时禁用上一首。
- 专辑曲目下方：展开「社区」，可点赞、发 140 字短评、删除自己的短评和阅读 repo；列表按需分页。
- 社团页：关注 / 取消关注，成功后同步更新关注动态。
- 搜索用户，或点击短评、repo、支持者榜中的头像昵称，可进入已购 / repo / 关注 / +2 dB 主页；「我的」也可进入个人主页。
- repo 正文和图片原生展示，回复入口仍使用网站。

写操作使用当前账号的 CSRF 表单，完成后重新读取网站状态；网络结果不确定时不自动重发。自动化测试使用模拟请求，不会替用户发短评、点赞或改变关注关系。

CI 默认执行 156 项核心回归测试，并编译完整 iOS 应用及测试目标。GitHub 的 Xcode 27 模拟器曾在 173 项测试通过后卡住结果收集，因此运行模拟器测试暂作为 Actions 手动运行时的 `run_simulator_tests` 选项；它仍会报告实际失败，不会忽略错误。
