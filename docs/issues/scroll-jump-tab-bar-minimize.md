# 页面滚动到顶部时跳动（标签栏自动收起引起）

状态（2026-10-26）：首版简化转场被用户否定；当前改为修改本地 LN，使原转场引擎支持系统附件作为起点。下面的首版验证、调查过程与撤回清单保留为历史记录，不代表当前实现的验收结果。

版本对比记录（2026-10-26）：曾按用户要求临时回退到 01:19“封面拉成长条已修复”的状态，并通过封面／开关定向回归后安装到真机。用户随后要求回到最新版本，现已从备份精确恢复该次临时回退前的源码，包含手势灵敏度、距离／速度判定、即时接管圆角和 0.32～0.46 秒弹簧；此前撤回的 cubic 曲线仍未恢复。后续路线待讨论。临时版本源码与安装包、回退前源码均留存于 `/tmp/neodizzy-artwork-checkpoint-rollback-20261026-g54ume82/`。

用户对比反馈：两个版本的收起动画有同样的问题。问题在后续手势和曲线优化前已存在，下一步排查应覆盖两版共有的系统附件适配；具体是否由几何、材质或层级交接造成，尚未确认。

恢复最新版本后，静态边界、Release 构建及 `externalPanUsesDistanceOrDeliberateFlickAndPreservesCancelledLayout()` 通过（1 通过、0 失败、0 跳过），已安装并启动到「溪泠」。首次构建因旧版头文件预编译缓存失效而中断，清理 LN 的对应缓存后通过，源码未因构建调整。证据及独立保存的最新安装包：`/tmp/neodizzy-restore-latest-20261026-jx6gmg2t/`。

## Instruments 定向修复（2026-10-26）

33 秒真机 SwiftUI trace 中，松手处理链多次连续占用主线程约 30～45ms；累计采样中约 72% 包含同步布局，调用栈可见 `_repositionPopupContentMovingBottomBar:animated:` → frame 更新 → 隐藏导航控制器／导航栏布局。重新抓取另有暂停、整理已有动画的开销。采样耗时受 Instruments 开销影响，不能直接当作无采样条件下的帧率。原始证据：`/tmp/neodizzy-player-instruments-Ic3poL/player-connected.trace`。

按用户同意的方向，本轮仅做定向性能修改：

- 使用既有 `LNPOPUP_EXTERNAL_ACCESSORY_ONLY` 编译开关，停止创建仅用于 LN 关闭按钮布局测量的隐藏导航控制器；缺少该控制器的路径显式跳过依赖它的布局。
- 系统附件模式不再强制布局不可见的 LN bar；播放器和内容容器尺寸未变时，不重复赋值 frame。
- 外部转场材质按既有独立明暗层直接初始化，去掉紧接着被覆盖的临时效果赋值。
- 保留封面过渡、文字不单独动画、系统附件及标签栏自动收起。普通 Release 构建不启用此前的诊断采样。

用户要求减少测试并直接安装：仅执行静态模块边界检查、差异检查与 Release 构建，不运行单元测试、全量回归或删除矩阵。改善幅度尚未做修复后的 Instruments 对照，真实手感由本次安装后复现确认。

## 手势退出卡顿诊断版本（2026-10-26）

用户反馈退出中途短暂停顿，要求诊断版本自行复现。`scripts/player-transition-diagnostics.py prepare --device 溪泠` 构建并安装启用 `PLAYER_TRANSITION_DIAGNOSTICS` 的 Release；普通构建不启用采样。配套 `collect --device 溪泠` 从 App 的 `Documents/PlayerTransitionDiagnostics` 拉取 JSON，并生成主线程回调间隔摘要。

采样从展开／拖动／关闭开始，到展开或回弹完成／关闭完成结束，每段最多 1800 个采样或 20 秒；只在动画结束后异步写文件，保留最近 30 段。不记录歌曲、账号或网络数据。字段包含回调间隔、display link 目标间隔、实际 presentation 卡片 frame、内容尺寸、portal 是否存在及手势／生命周期时间点。这些数据可定位时间点和几何交接，不能单凭 callback gap 认定 GPU 丢帧或具体根因。需要 CPU 调用栈时再对同一过程录制 Instruments。

复现时连续做几次拖动关闭、短拖回弹和展开中重抓，最后让动画完全落定，再执行 collect。安装普通构建可停止诊断；采集脚本不删除手机上的原始记录。

## 全屏转场尺寸与材质连续性（2026-10-26）

后续按用户要求收窄：仅封面执行独立收回动画，外部附件不再创建随卡片移动的迷你文字／控制按钮映射；真实系统附件文字留在原位，全屏文字随页面整体退出，没有单独的文字变形或飞行动画。该纯展示调整通过静态边界检查及一次 Release 增量构建，未新增或重复运行测试。

- 保留系统 `tabViewBottomAccessory`、标签栏 `.onScrollDown` 自动收起及现有 LN 拖动状态机；没有改动曲线、时长或播放业务。
- 外部附件路径原先在动画准备阶段直接切换目标材质，关闭时还把全屏过渡层改成附件的明暗样式。现在全屏与附件分别使用固定样式的效果层，通过动画改变效果；全屏封面背景仍留在实时内容映射中，不在关闭开始时移除。临时附件效果在落定前退场，真实系统附件始终由系统管理。
- 全屏内容映射保留完整 viewport 尺寸，由变化的外框居中裁切；不再随附件宽度改变映射层宽度。展开中重抓转为真实内容时也保留相同居中偏移，拖动及回弹继续由原状态机处理。
- 在现有两个播放器回归方法中加入实际过渡层的尺寸、居中、明暗样式和材质层透明度检查，并检查展开重抓的内容中心。静态模块边界、Release 编译及这两个真机回归方法通过（2 通过、0 失败、0 跳过）；未运行全量回归或物理删除矩阵。Release 首次测试编译因未启用 testability 失败，命令添加 `ENABLE_TESTABILITY=YES` 后通过，发布工程配置未修改。证据：`/var/folders/hh/7ptm1jpx2yjd35t2bgczks9m0000gn/T/neodizzy-player-continuity-20261026-eixhpcwa/final-targeted-v2.xcresult`。已查看稳态与关闭截图，但 `drawHierarchy` 截图不能证明逐帧材质连续；真实触摸及最终观感仍待验收。日志仍有 LN 已有的 appearance callback 警告，本次未扩大处理生命周期。

## 方案 C：原 LN 引擎接入外部附件

- 系统 `tabViewBottomAccessory` 继续承载迷你播放器；它的真实 `UIHostingController.view` 和 `UIImageView` 通过 `LNPopupExternalTransitionSource` 提供给 LN，不使用透明测量标记充当动画内容。
- 独立透明 UIKit 全屏容器承载 LN。复用原 LN 的 Preferred / Generic 动画器、实时 portal、玻璃过渡层、分阶段时序、封面圆角和拖动状态机；`NowPlayingView` 恢复 `.popupTransitionTarget()`。
- 隐藏的 LN 逻辑 bar 仅为原状态机提供几何坐标；不绘制第二条迷你播放器，不修改系统附件的位置、层级或宿主安全区。
- 本地包以 `LNPOPUP_EXTERNAL_ACCESSORY_ONLY` 关闭对宿主 tab/navigation/window/safe-area 的全局 hook；外部路径绕过底栏布局、层级重排及递归接管子滚动手势。普通全屏内容及按钮区域可向下拖动，滑条保留编辑手势；在顶部起手的列表可交给播放器收起。
- SwiftUI 仅在 LN `didClose` 完成后更新关闭状态和后续导航；关闭中收到新的展开请求会完成旧容器清理后重新展开，不触发旧导航。
- 静态模块边界检查、Release 编译、iPhone 17 真机定向回归通过：`PlayerPopupTests`、`ShellChromeIntegrationTests`，以及 `NowPlayingPortTests` 的呈现几何与队列慢速滚动，共 5 个方法、6 次执行，0 失败、0 跳过。覆盖真实外部视图接入、系统附件位置和宿主安全区稳定、关闭绑定、快速重开、隐藏恢复。证据：`/tmp/neodizzy-ln-external-20261026/targeted-v3.xcresult`。
- 已查看展开稳态截图。关闭中截图由 `drawHierarchy` 捕获，不能当作屏幕逐帧动画验证。原社团页滚动跳动、真实手指拖动完成／取消及连续打断手感仍需用户验收；本轮未运行全量回归或物理删除矩阵。
- 通过回归的 Release 测试产物已安装并启动到 iPhone「溪泠」。

### AM 录屏对照：补齐附件交接（2026-10-26）

- 参考用户录屏 `ScreenRecording_10-26-2026 11-38-15_1.MP4`（1206×2622、60fps、约 4.42 秒）。逐帧可见：收起初段仍保留带背景的整张卡片，迷你内容提前出现，封面独立缩小落位，卡片后段逐渐透明。这是画面观察，不能据此确认 AM 的内部 API、触摸释放时刻或精确动画参数。
- 移除 `willClose` 对完整播放器背景的提前隐藏及 SwiftUI rootView 重写，让背景留在原有实时内容 portal 内，随卡片裁切与分阶段淡出。系统附件本身的材质不被覆写。
- `LNPopupExternalTransitionSource.containerView` 单独提供几何；App 通过公开 `UITabBarController.bottomAccessory.contentView` 查找包含真实迷你内容的附件容器。LN 固定采样容器、内部内容偏移与封面窗口坐标，分别驱动外框与内容，避免把内部 hosting bounds 当成全部几何。容器无效时 core 与动画器均回退真实内容。读取的是公开容器边界，不声称取得系统玻璃阴影外沿，也没有硬编码额外边距。
- 普通拖动顶边上限、50% 判定及收起目的地统一为附件容器顶边，修复长拖到附件下缘后松手向上折返的路径。提前接管时保留已有可见位置；若旧动画位置已超过落点，仅禁止继续扩大超出量，避免接管首帧突跳。
- 保留 0.32～0.46 秒弹簧公式、24pt／一屏每秒的快速下甩规则、严格超过 50% 的距离规则、原分阶段透明度与取消／圆角保护；本轮不另行调曲线。
- 回退前源码、录屏抽帧和本轮验证证据目录：`/tmp/neodizzy-am-handoff-20261026-hhodqeoq/`。
- 静态模块边界、Release 编译及两个现有方法 `popupSynchronizesNativeDismissalAndSuppression()`、`externalPanUsesDistanceOrDeliberateFlickAndPreservesCancelledLayout()` 通过（2 通过、0 失败、0 跳过），涵盖真实容器登记／闭合端点、长拖松手 presentation 顶边连续及原取消／接管路径。证据 `targeted-v1.xcresult`；未扩大到全量或删除矩阵，最终动画观感仍由用户实机对照录屏验收。

### 录屏反馈：封面被拉成长条（2026-10-26）

- 用户录屏 `ScreenRecording_10-26-2026 01-11-06_1.MP4` 显示：展开初段和收起末段，封面被拉成窄高竖条；关闭完成后消失，并非完成后的视图泄漏。
- 根因是迷你封面 `UIImageView` 没有明确纵向尺寸契约。SwiftUI 外层方形布局和裁剪掩盖了图片视图的实际高度，LN 转换真实 bounds 后得到错误的转场端点。换成 900pt 大图的真机回归复现了宽高差 860pt；原 16pt 纯色测试图漏掉了该问题。
- `PlayerMiniatureArtwork` 现在通过 `sizeThatFits` 采用 SwiftUI 提议的两维尺寸，并降低纵向 intrinsic 优先级。保留原 LN 动画器、portal 和时序。
- 已保留大图及真实源视图方形／不超出附件高度的回归断言。真机定向流程修复前失败、修复后通过（1 个方法，包含完整开关、重开与隐藏恢复），静态边界检查通过。证据：`/tmp/neodizzy-ln-artwork-bounds-20261026/repro.xcresult`、`fixed.xcresult`。实际手势画面待用户在更新版本复测。

### 首轮拖动、取消与关闭尾段反馈（2026-10-26）

- 恢复普通全屏内容的下拉范围，排除滚动视图、控件及横向手势；队列和歌词不被接管。
- 松手时，超过完整收起行程的 50%，或下拉至少 24pt 且向下速度达到每秒一屏，才完成收起。短距离慢拖、恰好 50% 的静止松手和被系统取消的手势回到全屏；不在拖动途中自动关闭。速度阈值是本次实现选择，未声称为 Apple Music 的内部参数。
- `popupTransitionInProgress` 暴露 LN 的实际内部转场状态，App 在拖动、回弹和关闭中不覆盖 LN 的位置；稳态也只有视口或安全区变化时才更新布局。新的拖动等待前一次转场完成。
- 用户确认截图异常发生在仍按着拖动时。修复一条可导致直线顶边的时序：`began` 被前一次动画忽略，而后续 `changed` 实际启动拖动时没有恢复屏幕圆角。现在在真正启动拖动的位置重新启用圆角。实际触摸复现是否消失仍需更新版本复测。
- 仅在 `willClose` 确认收起时无动画隐藏全屏封面背景，拖动及取消仍保留背景。覆盖传入 SwiftUI 的环境值，避免外层环境被内容根视图覆盖。
- 关闭动画的临时玻璃采用系统附件的明暗样式，并在动画时间的 55%～90% 阶段淡出；迷你内容与封面继续归位，避免末尾临时玻璃和真实系统附件玻璃叠加。
- 当前 Release 真机定向回归：`PlayerPopupTests` 3 个方法通过，0 失败、0 跳过；静态模块边界检查通过。新增回归在 iPhone 上向实际 LN 手势识别器注入状态、位移与速度，调用原状态机，覆盖慢拖、轻微快拖、快速下甩、距离阈值、取消、强制布局时的位置稳定以及背景切换。证据：`/tmp/neodizzy-ln-gesture-20261026/targeted-v1.xcresult`。这不代替真实手指输入及玻璃逐帧观感验收；本轮未运行全量回归或物理删除矩阵。

### 灵敏度与连续接管（2026-10-26，后续修订）

- 上轮为防跳变而禁止整个转场期间起拖，导致刚展开或回弹未完成时新的触摸失效。本轮增加 `popupInteractionCanBegin`，区分可以接住的展开／回弹与已确认的关闭、正在进行的拖动。接住时读取实际 presentation frame，在旧动画清理 portal 后恢复当前位置；用动画代次隔离旧完成回调，最终仍补齐呈现生命周期和事件队列完成。
- 下拉不再排除所有 `UIControl`：按钮保留点击且允许拖动取消点击，滑条等持续编辑控件仍独占操作。使用真实初始触点视图固定归属。滚动视图在顶部起手可交给播放器；确认下拉后暂停该滚动视图并固定在顶部，手势结束或播放器移除时恢复。
- 主 pan 保留 UIKit 的完整触摸跟踪，LN 只在累计下移达到 6pt 且纵向位移至少为横向的 0.8 倍时接管；初始方向不明确时不移动播放器。与明确命名的切歌 pan 及滚动视图自身 pan 协调；下拉接管会取消切歌预览、无动画归零，避免松手误切歌。横滑要求横向累计位移超过纵向的 1.25 倍。
- 本轮不是任意滚动位置的手势接力：从列表中间起手仍交给列表；在顶部起手后先上滚、再返回顶部的同一次触摸会重新检查顶部位置并重置旧位移。
- 展开动画的临时内容和封面 portal 不接收触摸，底层识别器在展开开始时便挂载；中断后恢复原始封面圆角和阴影。极早展开时的封面形态衔接仍需真实手指观察，状态回归不能证明逐帧观感。
- 按用户要求减少验证：静态模块边界检查、Release 构建及现有手势回归 `externalPanUsesDistanceOrDeliberateFlickAndPreservesCancelledLayout()` 通过（1 个方法，0 失败、0 跳过），覆盖展开／回弹中重抓后的真实 presentation 位置连续与后续状态收尾。证据：`/tmp/neodizzy-ln-sensitive-20261026/targeted-v2.xcresult`。首轮方法过滤未命中，只有编译结果；修正过滤后复用产物执行，不重复构建。未运行全量回归、UI 自动化或删除矩阵，触摸仲裁及最终手感交由用户真机验收。

### 即时接管圆角与收起节奏（2026-10-26）

- 用户实测确认：刚展开就下拉时上角仍会变直角。原因是接管保留了展开中带水平缩进的 frame，而 LN 原圆角判断要求左右边缘精确贴住 window；仅设置 `applyScreenCorners` 仍得到零圆角。现在在拆除旧 portal 前采样可见效果层的 presentation 四角，并保留到拖动及后续收尾完成。独立外部表面的设备圆角也不再依赖左右贴边；无有效采样时取当前 window 的圆角，不硬编码半径。
- 收起的主要位移原本由弹簧驱动，但构造动画时丢弃了已传入的松手速度。本轮将外部附件关闭的向下速度按剩余行程归一化（上限 4/s），阻尼设为 1，时长按剩余距离调整为 0.32～0.46 秒；目标是接续松手运动并平滑减速。其他展开／回弹参数、封面和玻璃淡出的阶段保持原设置。该参数为本项目调校，最终观感需用户真机判断。
- Release 构建、静态模块边界检查及唯一现有手势回归通过（1 个方法，0 失败、0 跳过）。该方法新增接管后、拖动后及强制布局后的实际 `layer.cornerRadii` 检查，两侧上角均大于零；没有增加测试组或另做性能／全量验收。证据：`/tmp/neodizzy-ln-corners-motion-20261026/targeted-v1.xcresult`。

### 收起缓出与视觉交接重调（2026-10-26，已撤回）

用户要求退回首次单独提出“收起动画还是太草率，优雅一点，不要做线性的”之前。以下尝试均已撤回，当前恢复上一节的 0.32～0.46 秒弹簧、原分阶段交接和确认收起时隐藏背景的处理，保留手势灵敏度与即时接管圆角修复；下述背景原因判断未获用户认可，不作为已确认结论。

回退验证：静态模块边界及 Release 编译通过。仅运行已有手势回归；首轮在第二次展开的瞬时状态等待超时，随后未取得 presentation frame，同一产物不改代码复跑通过（1 个方法，0 失败、0 跳过），首次超时原因未确认。证据：`/tmp/neodizzy-ln-motion-rollback-20261026/targeted-v1.xcresult`、`targeted-v2.xcresult`。未扩大测试组或运行全量／删除矩阵。

- 用户再次反馈收起过于草率。上轮缩短弹簧时长的方案被替换：外部附件收起改为明确的 cubic ease-out（控制点 `(0.22, 0.78)`、`(0.25, 1)`），整个位置、尺寸与封面共用这一曲线；时长为 0.56～0.62 秒，快速下甩只小幅加快，不再因剩余距离短而压缩尾段。展开和取消回弹保持原弹簧。
- 封面交叉淡化、全屏内容／临时玻璃淡出、迷你内容淡入统一到动画时间的 15%～55%。全屏内容仅随父效果层淡出，去掉父子同时淡出带来的透明度相乘；后半段留给封面与迷你内容缓慢落定，避免几何已靠近终点时玻璃仍在叠加。
- 用户随后明确“封面和文字都动，但背景没跟着收缩”。当时将 `willClose` 隐藏全屏背景判断为原因，尝试移除 `nowPlayingBackdropVisible` 开关及关闭时的 rootView 重写，让全屏背景保留在收缩中的源 portal 内。用户否定了该原因判断，并要求回退；这项背景改动现已撤销。
- 最终 Release 构建、静态边界及 `popupSynchronizesNativeDismissalAndSuppression()` 通过（1 个方法，0 失败、0 跳过），证据 `/tmp/neodizzy-ln-eased-close-20261026/targeted-v4.xcresult`。现有用例增加实际 presentation frame 的逐帧 JSON，检查中点进度大于 65%、后半程平均速度小于前半程一半；该检查证明容器缓出，不等于完整视觉验收。此前 v1 曾在约 39ms 内关闭且未采到动画，补运行状态记录后 v2/v3 连续通过；该次跳过的具体原因未确认。恢复背景后 v4 通过，没有扩大测试组或执行全量回归。

## 方案 C 首版（已被替换）

- 迷你播放器使用系统 `tabViewBottomAccessory`，随系统标签栏在 expanded / inline 布局之间切换；保留播放控制、标题滚动与横滑切歌。
- 全屏播放内容继续使用原有 `NowPlayingView`。独立 UIKit 呈现层适配 LNPopupController 的动画时序与封面衔接，支持点击／上滑展开、把手或封面区域下拉收起、未完成拖动弹回。
- 全屏呈现时保留系统附件及底层页面占位；拖动采用固定容器坐标与固定内容安全区。队列和歌词滚动不接管为收起手势。
- 主应用解除 LNPopupUI / LNPopupController 链接，原包源码与许可证保留作参考，避免它们的标签栏全局 hook 继续运行。
- 首版边界：展开动画的约 0.5 秒内暂不接受反向下拉；展开后支持交互完成和取消。连续打断展开的手感待后续完善。
- 已通过静态模块边界、Release 编译与签名检查，产物未包含 LNPopupController 运行时符号。
- iPhone 17 真机定向回归通过：`PlayerPopupTests` 4 项、`ShellChromeIntegrationTests` 1 项，以及 `NowPlayingPortTests` 的呈现几何稳定（封面／队列两个参数）和队列慢速滚动，共 7 个测试方法、8 次执行，0 失败、0 跳过。证据：`/tmp/neodizzy-native-player-20261026/targeted-v3.xcresult`、`geometry.xcresult`。
- Release 测试版已安装并正常启动。原复现页面的滚动跳动、真实手势手感、快速连续操作由用户继续验收；本轮未运行全量回归或物理删除矩阵。

## 现象

- 在页面上从中段往上滚到顶部（或往下滚）时，内容在一帧之内突然移动 20～40pt，看起来像页面“跳”了一下。
- 内容越短的页面越明显。最稳定的复现页面是 DizzyLab 社团页“北极圈 Arcticlab”，只有 4 张作品，一滑就到顶。
- 只有滚动内容在跳。导航栏（返回按钮）一像素都不动。

## 调查过程和结论

### 1. 录屏逐帧分析（60 帧/秒）

- 逐帧比较相邻两帧，测量内容的垂直位移；同时看屏幕底部的亮度，判断标签栏是展开还是收起。
- 正常滚动时，位移是连续变化的。跳动表现为单帧突变，例如先回退 4pt，下一帧又前冲 27pt。
- **每一次跳动都恰好发生在标签栏开始收起或展开的那一帧**：往上滑时在展开的瞬间，往下滑时在收起完成的瞬间。

### 2. 屏幕诊断数值（`onScrollGeometryChange` 加 `GeometryReader`）

- 以每秒 6 次取样，滚动区域的上下内边距（116 / 139）、上下安全区（116 / 139）、滚动区域和页面高度（619）始终不变。
- 当时内容总高度在 891 和 1055 之间来回变化。原因是页面外层用了 `LazyVStack`，并且混放了种类不同的区块，屏幕外区块的高度靠估算，估得不准。
- 把外层改成 `VStack`、只让歌曲行懒加载，并把社团页的横向 `LazyHStack` 改成 `HStack` 之后，内容高度稳定了（社团页各区块高度每帧都不变），**但跳动仍然存在**。所以懒加载估算只是一个次要问题，不是这次跳动的根源。这些改动随后也都撤回了，见文末。
- 页面没有被重新加载（`Loadable` 一直是 `isLoading == false`、有值），所以和下拉刷新无关。

### 3. 对照实验（关键证据）

- 把 `RootView.swift` 里的 `.tabBarMinimizeBehavior(.onScrollDown)` 改成 `.never` 后，**社团页不再跳**。
- 结论：跳动由“标签栏随滚动自动收起、展开”引起。

### 4. 为什么 Apple Music 收起标签栏却不跳

- 推测 Apple Music 的迷你播放器放在系统的标签栏底部附件里（iOS 26 的 `UITabAccessory`，SwiftUI 里是 `.tabViewBottomAccessory`）。标签栏收起、附件改成与标签栏并排、内容区边距调整，都由系统在同一次布局、同一个动画里完成，和滚动保持同步。
- 我们的迷你播放器由第三方库 LNPopupController 绘制，它不是系统附件。它在 iOS 26 上模仿“收起后与标签栏并排”的方式如下：
  - 用私有接口监听标签栏是否收起：`UITabBar` 的 `_isMinimized` 和 `_minimizedStateDidChangeHandler`，见 `Packages/LNPopupController/.../Private/Minimization/UITabBar+LNPopupInheritedBarMetricsSupport.mm`。
  - 收到通知后，在 `LNPopupController.mm` 的 `tabBar:didMinimize:` 里先调用 `_ln_setIgnoringLayoutDuringTransition:YES` 暂停布局，再用 `dispatch_async` 推迟到下一轮主线程，用自己的 `UIViewPropertyAnimator` 分段挪动迷你播放器、调整边距（带 0.2 左右的 `delayFactor`）。
  - 这些布局更新比系统晚一拍、分几次落地，其中一次改动正好撞上滚动视图的惯性或回弹，就成了单帧跳动。
- 已排除：只在 `_ln_updatePopupBarContainerInsets` 里固定底部安全区（让它不随收起、展开变化）**无效**。问题在于时序，而不只是安全区的数值。这个补丁已撤回。
- Apple Music 全屏播放器的打开和下拉关闭，并不是系统的 zoom 过渡。zoom 的下拉返回可以朝任意方向自由拖动；Apple Music 和我们现在一样，只能竖直方向移动。推测这是 Apple 自己实现的呈现方式，没有公开接口。

## 最初讨论的可选方案（历史）

| 方案 | 改动 | 标签栏收起 | 风险 / 代价 |
|---|---|---|---|
| A. 关掉标签栏自动收起 | `RootView.swift` 一行：`.tabBarMinimizeBehavior(.never)` | 失去 | **已验证有效**。最稳，但没有 iOS 26 往下滚时标签栏变小的效果 |
| B. 保留收起，让迷你播放器不跟着换位置 | 关掉 LNPopup 的 `popupBar.inheritsBottomBarMetrics`（可以在 `PlayerPopup.swift` 的 `.popupBarCustomizer` 里设） | 保留（迷你播放器不再与标签栏并排） | **未验证**。LNPopup 的 `didMinimize` 处理仍会运行（暂停布局、异步重新布局），跳动可能依旧 |
| C. 迷你播放器改用系统附件，全屏播放器自己实现竖直拖动的转场 | `.tabViewBottomAccessory` 承载迷你播放器；全屏播放器用 UIKit 自定义转场（`UIViewControllerTransitioningDelegate` 加只认竖直方向的交互式拖动手势），包括封面飞行动画 | 保留，和 Apple Music 一致 | 大改造：要替换 LNPopupController，播放页里依赖它的细节都要迁移（拖动收起、继续播放列表里针对 LNPopup 的处理、迷你播放器左右滑动切歌用的 `popupItems(selection:)` 等），手感要在真机上反复打磨 |

当时建议先用 A 或 B 压住问题。用户随后选择 C；目前的 C 已调整为“系统附件 + 原 LN 外部转场源适配”，见文首，不再采用首版的独立简化动画。

## 新会话复现与验证

- 复现页面：DizzyLab › 北极圈 Arcticlab 社团页。从中间往上滑到顶部、再往下滑，来回几次。
- 诊断手段：
  1. 录屏后用 ffmpeg 以 60 帧/秒抽帧，比较相邻帧中间一条竖直区域的亮度曲线，求出每帧位移。单帧突变超过约 18pt 的就是跳动。
  2. 需要数值时，临时在 `AlbumDetailScrollView` 上加 `onScrollGeometryChange` 读数叠加层（偏移、上下内边距、内容高度、容器高度、安全区）。注意每秒 6 次的取样会漏掉瞬时变化。
- 模拟器目前不可用（安装 App 时会卡死），只能在真机上验证。

## 本次撤回的改动（调查前的状态）

以下都已撤回，代码和调查开始前一致：

- `RootView.swift`：`.tabBarMinimizeBehavior(.never)` 改回 `.onScrollDown`。
- LNPopupController 里固定底部安全区的补丁。
- `AlbumPresentation.swift` 和 `LabelDetailView.swift` 里的诊断读数代码。
- 以下页面从“外层 `VStack`、只有歌曲行懒加载”改回原来的外层 `LazyVStack`：DizzyLab 社团页和专辑页，网易云、QQ 音乐的专辑/歌单页和歌手页，“喜欢的歌”，本地歌单，本地专辑，资料库“歌曲”页，“最近播放”。社团页的两排作品架和专辑页的评论预览，从 `HStack` 改回 `LazyHStack`。
  - 注意：这组改动修掉的是一个真实存在的次要问题，即懒加载估算导致内容高度在 891 和 1055 之间来回变化。修复主问题后如果还有残余的小跳动，可以再考虑恢复这组改动。
