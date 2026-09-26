# 第三方来源 / Third-Party Notices

## MeloX

- 来源：<https://github.com/youshen2/MeloX>（个人修改版 MeloX_Modified）
- 许可证：GNU General Public License v3.0
- 用途：以下文件移植自 MeloX，并在文件头注明了来源和改动：
  - `Core/Playback/PlaybackQueue.swift`、`PlaybackPersistence.swift`、`NowPlayingSession.swift`、`AudioSessionConfigurator.swift`
  - `Core/UI/ArtworkImage.swift`，`Core/UI/LoadStateViews.swift` 里的分页底栏
  - `Features/Player/MiniPlayerView.swift`
  - 播放页 `Features/Player/NowPlaying/`：Apple Music 式动态背景（`AppleMusicBackdropShaders.metal` 原样移植）、播放控制按钮样式（原样移植）、大封面页、队列页、底部控件和「…」菜单（按 NeoDizzy 精简）
- 主页面标题的固定 / 滚动设置与下拉补偿逻辑移植自 `MeloX_Modified/MeloX/Shared/Components/PageHeader.swift`，改用 NeoDizzy 的头像入口与泛型页头。
- `PlayerStore` 参考了 MeloX 的结构，按需重写。M3 文件夹扫描按 NeoDizzy 的专辑对应关系格式独立实现。

## Nuke

- 来源：<https://github.com/kean/Nuke>
- 许可证：MIT
- 用途：封面图片的加载、解码与缓存。

## SwiftSoup

- 来源：<https://github.com/scinfu/SwiftSoup>
- 许可证：MIT
- 用途：解析社团页、标签页、搜索页等没有 JSON 接口的网页。

## ZIPFoundation

- 来源：<https://github.com/weichsel/ZIPFoundation>
- 许可证：MIT
- 用途：解压已购专辑 ZIP，校验文件完整性并读取不同编码的文件名。

## NeoBili

- 许可证：MIT，与本项目同一作者
- 用途：页头（`PageHeader`）的样式与标签页组织方式参考自 NeoBili；账号与钥匙串存储将参考其实现（M2 起）。

## DizzyLab

- 界面配色取自 DizzyLab 官网公开的样式表（`#1a1a1a` 底色、`#f0ad4e` 购买色等）。
- NeoDizzy 不包含 DizzyLab 的商标、Logo 或任何音乐内容。
- 单元测试样本 `NeoDizzyTests/Fixtures/` 保存了少量公开页面和接口响应的片段，只用于解析测试。样本已删去脚本、导航、页脚和其他用户的头像与昵称。

应用图标的立体字母构图参考 NeoBili（MIT）；NeoDizzy 的 D 字形、黑金配色和 SVG 由本仓库的 `scripts/generate-app-icon.swift` 生成。
