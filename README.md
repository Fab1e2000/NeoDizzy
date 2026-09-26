# NeoDizzy

非官方的 [DizzyLab](https://www.dizzylab.net) iOS 第三方客户端，使用原生 SwiftUI 构建。

> NeoDizzy 与 DizzyLab 及其运营方不存在隶属、合作或授权关系。详见 [免责声明](DISCLAIMER.md)。

*An unofficial, open-source SwiftUI client for the DizzyLab doujin music store. Not affiliated with DizzyLab.*

## 当前状态

项目处于起步阶段。目前只有深色主题、标签页框架和各页面的占位内容，还不能浏览、播放或购买。

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M0 骨架 | 工程、深色主题、标签页框架、真机部署脚本 | 已完成 |
| M1 浏览 | 专辑列表与详情、社团、标签、搜索、排行榜、试听播放 | 未开始 |
| M2 账号 | 登录、已购库、完整版串流、关注动态 | 未开始 |
| M3 离线 | 下载到你选的文件夹，在 App 内离线播放 | 未开始 |
| M4 购买 | 自定价格 / BOOST，支付宝付款 | 未开始 |
| M5 社区 | 点赞、短评、repo、随便听听、用户主页、关注社团 | 未开始 |

完整规划见 [docs/PLAN.md](docs/PLAN.md)，网站接口梳理见 [docs/SITE_API.md](docs/SITE_API.md)。

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

## 许可证与致谢

NeoDizzy 以 [GPLv3](LICENSE) 发布。播放相关代码将移植自同样以 GPLv3 发布的 [MeloX](https://github.com/youshen2/MeloX)，界面组织参考了 NeoBili。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

请支持并尊重创作者：在 DizzyLab 购买后下载的作品仅供个人使用，不要上传发布到任何公开的网络空间。
