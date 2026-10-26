# 第三方来源 / Third-Party Notices

## MeloX

- 来源：<https://github.com/youshen2/MeloX>（个人修改版 MeloX_Modified）
- 许可证：GNU General Public License v3.0
- 用途：以下文件移植自 MeloX，并在文件头注明了来源和改动：
  - `Core/Playback/PlaybackQueue.swift`、`PlaybackPersistence.swift`、`NowPlayingSession.swift`、`AudioSessionConfigurator.swift`
  - `Core/UI/ArtworkImage.swift`，`Core/UI/LoadStateViews.swift` 里的分页底栏
  - `Features/Player/MiniPlayerView.swift`
  - 播放页 `Features/Player/NowPlaying/`：Apple Music 式动态背景（`AppleMusicBackdropShaders.metal` 原样移植）、播放控制按钮样式（原样移植）、大封面页、队列页、底部控件和「…」菜单（按 NeoDizzy 精简）
- 专辑和歌单的封面布局、玻璃播放操作、平均取色、预渲染模糊与渐变背景适配自上游 `PlaylistDetailContent.swift`、`ArtworkAccentColorProvider.swift`，复用 NeoDizzy 的 Nuke 预加载缓存。
- 专辑曲目列表 `Features/Disc/AlbumPresentation.swift` 移植上游 `Features/Playlist/PlaylistTrackList.swift` 的布局和当前曲目样式，操作适配 NeoDizzy 的播放及本地标签编辑。
- 主页面标题的固定 / 滚动设置与下拉补偿逻辑移植自 `MeloX_Modified/MeloX/Shared/Components/PageHeader.swift`，改用 NeoDizzy 的头像入口与泛型页头。
- `PlayerStore` 参考了 MeloX 的结构，按需重写。M3 文件夹扫描按 NeoDizzy 的专辑对应关系格式独立实现。

- 网易云音质档位、按网络选择与降级顺序、播放日志协议、心动模式接口与喜欢列表入口，参考 MeloX 本地分支 `b8bc60f` 的 `MusicQuality.swift`、`PlaybackHistoryRecorder.swift`、`NeteaseAPI+IntelligenceMode.swift` 和 `LibrarySongsView.swift`，适配模块设置、共享播放器与账号隔离。

- 「继续播放」页直接移植 MeloX `b8bc60f` 的 `NowPlayingQueuePage.swift`，包括列表、双位置模式栏、空状态和拖动排序；数据类型、本地化、竖屏外置曲目头及底部控件高度接入 NeoDizzy。队列重排逻辑直接移植 `PlaybackQueue.moveUpcomingSongs`。

- 全屏播放器进一步直接移植同一 MeloX `b8bc60f` 的封面页、横屏布局、曲目头、底部控件，以及 `NowPlayingMotionSpec`、`NowPlayingTransitionCoordinator`、`NowPlayingInterruptibleProgress`、页面呈现和控件转场源码。浮动歌词按钮替换为 AVRoutePickerView，歌曲操作接模块的喜欢/更多接口。歌词载入和渲染继续使用 NeoDizzy 的 LocalLyrics 适配层；未引入 MeloX 的 AutoMix、播客、其他歌词风格及其设置体系。
- 播放器默认背景直接移植同一版本的 `NowPlayingAppleMusicBackground.swift` 与着色器参数封装：使用原封面 AsyncImage、相同模糊与明暗叠加、歌词页 pinch 过渡；频谱响应保持上游默认关闭，播放时钟接 NeoDizzy。

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
- 专辑左侧防误触区域与宽度设置参考 `Core/UI/LeftEdgeTapDeadZone.swift`。
- 用途：页头（`PageHeader`）的样式与标签页组织方式参考自 NeoBili；账号与钥匙串存储将参考其实现（M2 起）。

## DizzyLab

- 界面配色取自 DizzyLab 官网公开的样式表（`#1a1a1a` 底色、`#f0ad4e` 购买色等）。
- NeoDizzy 不包含 DizzyLab 的商标、Logo 或任何音乐内容。
- 单元测试样本 `NeoDizzyTests/Fixtures/` 保存了少量公开页面和接口响应的片段，只用于解析测试。样本已删去脚本、导航、页脚和其他用户的头像与昵称。

应用图标「唱片箱」为本仓库原创设计，源文件与规范见 `design/`。

## TagLib 与 utfcpp（内嵌标签编辑）

- TagLib 官方源码：https://github.com/taglib/taglib ，版本 2.3.2，提交 `deadc2990767dfbda0701e0ab35fdeea653db08f`。
- 源码和许可证保存在 `Packages/AudioTags`，通过本地 SwiftPM 包编译，不依赖预编译二进制。TagLib 按其 LGPL-2.1 / MPL 双许可证分发，完整条款见包内 `COPYING*`。
- TagLib 使用的 utfcpp 固定为提交 `2d8e20b22dcb3e9b3c4f52103182ebda949c6089`，许可证见 `UTFCPP-LICENSE`。
- NeoDizzy 的桥接层只负责标签读写，不提供额外音频解码器；官方 C++ 源码未修改，构建配置及桥接由本项目提供。

## NeteaseCloudMusicApiEnhanced

- 来源：<https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced>
- `NeteaseCheckToken.swift` 的官方 Watchman SDK 初始化、就绪等待与按操作获取 token 流程参考 `module/register_checktoken_v2.js`；请求头与请求体的 token 用法参考 `module/playlist_subscribe.js` 和 `util/request.js`。未移植浏览器身份覆盖逻辑。
- 许可证：MIT，条款如下。

Copyright (c) 2013-2022 Binaryify

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## QQMusicApi

- 来源：<https://github.com/L-1124/QQMusicApi>，参考提交 `27861e51432ea6b6e88dc35c4e8c8e239c0339e8`。
- 许可证：GNU GPL v3.0 or later，与本项目的 GPLv3 许可兼容；上游完整许可见 <https://github.com/L-1124/QQMusicApi/blob/27861e51432ea6b6e88dc35c4e8c8e239c0339e8/LICENSE>。
- `Core/Modules/QQMusic/` 将上游 `modules/search.py`、`song.py`、`singer.py`、`user.py`、`album.py`、`songlist.py`、`top.py`、`recommend.py`、`lyric.py`、`login.py` 及 `core/versioning.py` 的 Web 请求契约适配为 Swift。音乐登录 Cookie 与在线会话验证、公共参数和歌曲地址字段沿用上游；扫码授权由官方网页完成；未嵌入 Python 运行时，也不依赖第三方托管服务。
- NeoDizzy 与 QQ 音乐及腾讯无隶属关系，不包含音乐内容或平台商标素材。

## LX Flow Music 日推请求参考

- 来源：[eohh-zhou/lx-flow-music-desktop](https://github.com/eohh-zhou/lx-flow-music-desktop)，参考提交 `14e254c733789cb1749f006b9da3a34e49fa3032` 的 `src/main/modules/winMain/rendererEvent/qqMusic.ts` 中 `getDailyRecommend`。
- 上游许可证：[Apache License 2.0](https://github.com/eohh-zhou/lx-flow-music-desktop/blob/14e254c733789cb1749f006b9da3a34e49fa3032/LICENSE)。本项目仅对照每日目录的请求契约，以 Swift 独立实现；未嵌入上游程序。

## Simple Music 搜索请求参考

- 来源：[Yyyangshenghao/simple-music](https://github.com/Yyyangshenghao/simple-music)，参考提交 `b7e1943ceb0cb8861bf3b0f1fa107c84e3a2ec49` 的 [`server/lib/qq-client.ts`](https://github.com/Yyyangshenghao/simple-music/blob/b7e1943ceb0cb8861bf3b0f1fa107c84e3a2ec49/server/lib/qq-client.ts)。
- 许可证：GNU GPL v3.0。QQ 分类搜索仅对照该项目的 module 键请求信封及省略 `comm` 的协议行为，以 Swift 实现；未嵌入其服务程序。

## LNPopupUI / LNPopupController

- 来源：https://github.com/LeoNatan/LNPopupUI （`60853564423524c9ed15cc74c5969d3e1ca666f1`）与 https://github.com/LeoNatan/LNPopupController （4.6.1）。
- MIT 许可证；源码及许可保留在 `Packages/LNPopupUI`、`Packages/LNPopupController`，应用内附带 `LNPopupLicenses.txt`。
- 主应用静态链接本地 fork。`LNPopupExternalTransitionSource` 让原 LN 动画器读取系统底部附件中自有内容和封面的真实视图；保留原 portal、玻璃过渡层、分阶段动画及交互状态机。
- 本地 `LNPOPUP_EXTERNAL_ACCESSORY_ONLY` 构建关闭 LN 对宿主标签栏、导航栏、窗口与安全区的全局 hook；独立容器承载全屏内容，不绘制 LN 自有迷你栏。转场仍沿用上游内部 portal 实现，不属于纯公开 API 重写。
- `NativePlayerPresentation.swift` 仅负责 SwiftUI 状态和独立 UIKit 容器的生命周期桥接。迷你播放器使用系统底部附件，全屏内容继续使用原有 MeloX 移植实现。
