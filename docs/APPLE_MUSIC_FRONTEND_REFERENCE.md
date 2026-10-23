# Apple Music 前端实现参考

整理日期：2026-10-23。用途：为播放器、歌词、背景与队列交互提供可追溯的实现资料。

本资料汇总社区公开的局部逆向、网页代码分析和独立复刻。它不代表 Apple Music 原始源码，也不代表已在当前 iOS 或 NeoDizzy 中验证。不同来源、版本和代码分支的做法分别保留；冲突项集中列于第 7 节。

## 1. 阅读方式与证据范围

以下标签用于区分结论的来源：

- **源码可见**：可以在公开实现中定位；本次没有运行该实现。
- **作者记录**：作者提供的逆向过程、调试输出或解释；本次没有在相同设备上独立重现。
- **推测**：原作者尚未确认的解释。
- **综合建议**：本文为工程落地提出的方案，不代表 Apple 内部架构。

不要把旧版本的参数当成跨版本常量，也不要把相似的视觉结果当成相同的渲染算法。一个项目内的文章、默认值、构造器和调用点也可能互不一致。

### 1.1 主要来源

| 编号 | 来源 | 研究对象与成果 | 公开范围 |
| --- | --- | --- | --- |
| LB | [LyricsBlossom 幕后记录][LB] | 作者分析 iPadOS 16.4 的原生 `MusicApplication`，公布歌词参数与部分 Swift 译文 | 软件闭源；公开译文有删减；不是完整可构建工程 |
| RQ | [Rahul：Reverse Engineering Apple Music iOS App][RQ] | 原生歌曲侧滑入队、队列拖动及调用链的调试笔记 | 未完成；作者因 iOS 18 队列行为变化而停止该研究 |
| AW | [Aadish Verma：背景逆向][AW] | 分析 Apple Music Web 压缩 JavaScript，重建背景效果 | [固定提交的 TypeScript 重建代码][AW-CODE]；网页与原生有差异 |
| AMLL | [Apple Music-like Lyrics][AMLL] | 独立实现歌词、背景、解析及框架绑定 | 公开源码；AGPL-3.0；不宣称恢复 Apple 原始前端 |

AMLL 的具体源码引用固定到本次检查的提交 `5fee356362353dbb24ce9bea3a62536478040de7`。AW 重建代码固定到作者文章所链接的提交 `4ef618ea2638a0c435d23f182f7aa10e30757ef6`。网页文章没有固定版本，应结合整理日期阅读。

### 1.2 补充实现

下列两个项目用于补齐原生转场与背景的实现选项，不作为 Apple 原生逆向证据：

| 编号 | 来源 | 可参考内容 |
| --- | --- | --- |
| SP | [AppleMusicStylePlayer][SP] | SwiftUI 的迷你播放器、展开卡片与手势转场 |
| FG | [FluidGradient][FG] | Core Animation / SwiftUI 流体背景替代方案 |

补充源码分别固定为 SP 的 `a0b5631417dec05d092c3c61df4679ed361743bf` 与 FG 的 `9ddda4cf23671ef0228e88681ec6210cb3e0d7f7`。下文链接均对应这些快照，参数不代表最新分支或 Apple 原生取值。

## 2. 歌词：原生逆向与独立组件

### 2.1 LB：能读到什么

**作者记录**：通过 IDA、Frida、FLEX 和 iPadOS 16.4 真机，把静态函数分析与运行时属性检查结合。研究对象包括歌词视图、布局、动画、图层与渲染行为。[来源][LB]

网页 HTML 内嵌 `code-specs` 与 `code-lyrics` 两个文本块；普通网页正文提取可能漏掉。它们是作者整理的 Swift 译文，不能视为 Apple 原始 Swift 文件。参数表、解析流程和其中的冲突见本节及第 7 节；完整软件仍为[闭源项目][LB-REPO]。

| 公开片段的定位 | 可参考内容 | 限制 |
| --- | --- | --- |
| `code-specs`：属性、预设、builder | 字体、行距、缩放、透明度、延迟与部分弹簧参数 | 声明与 builder 存在不同值，不能只抄默认值 |
| `code-specs`：spring 工厂及末尾说明 | 部分换行、按压与释放的运动参数 | 逐音节自适应弹簧、部分范围映射及通用工厂被删减 |
| `code-lyrics`：初始化、`assembleProcessedLines` | 由内部歌词对象组织行、词、声部与时序的译文 | 未完整展示 TTML/XML 文本解析并形成 `MSVLyricsSongInfo` 的前置过程；`processLyricsLine` 仅见索引 / 注释引用，没有公开函数体 |
| `code-lyrics`：方向与字典辅助函数 | 方向判断、COW / 哈希表等编译后实现线索 | 有缺失 helper 及命名冲突，不能直接作为通用解析器 |

少量参数候选如下，保持译文中的数值形式，不替作者补齐单位或适用条件：[片段来源][LB]

| 项目 | 片段可见值 | 解释范围 |
| --- | --- | --- |
| 字体 | 默认 `34 bold`；iPad `48 bold`；alternative `28 bold` | `UIFont` 的字号，不代表所有设备、版本共用 |
| 行距 / 背景声部间距 | `25` / `15` | `CGFloat` 数值，片段没有逐项声明长度单位 |
| 行延迟 | `0.05` | `Double` 数值，不在本文擅自改写成毫秒 |
| 换行弹簧 | `(1, 100, 18)` | 依次为 UIKit mass / stiffness / damping；不是实测 SI 数据 |
| 按压 / 释放弹簧 | `(1, 322, 24)` / `(2, 300, 50)` | 独立工厂参数，不覆盖换行参数 |

### 2.2 AMLL：可复用的实现层次

AMLL 将歌词显示与 React / Vue 绑定分开，并另设歌词格式解析及 TTML 模块。研究时应分别查看核心显示、时间推进、布局、滚动与逐词遮罩，避免只读框架封装后推断内部算法。[项目说明][AMLL-README]

**源码可见**：核心组件是 UI，不负责真实音频播放和歌词资源获取。行 / 词模型有毫秒时间戳，以及译文、音译、背景声部和对唱等字段；低精度歌词不能仅靠渲染器变成准确逐词歌词。[Core 说明][M-CORE]、[数据接口][M-INTERFACES]

#### 时间、行状态与排版

| 机制 | 固定快照中的处理 | 代码入口 |
| --- | --- | --- |
| 媒体时钟 | `setCurrentTime` 接收播放进度；`update(delta)` 推进视觉弹簧，两者分开 | [base][M-BASE]、[DOM update][M-DOM] |
| seek 检测 | 媒体 / 物理时间差的启发式判断；可显式传 `isSeek` | [seek-detector][M-SEEK] |
| 状态窗口 | playing groups 与 highlighted groups 分开，支持重叠行及唱完后的留亮 | [timeline][M-TIMELINE] |
| 间奏 | 大于等于 7 秒的空隙产生间奏候选，焦点可以转交间奏点 | [timeline][M-TIMELINE] |
| 排版更新 | 用时间线 diff 决定是否更新；缓存实测高度与前缀和，未知高度先估算 | [base][M-BASE]、[layout][M-LAYOUT] |
| 视觉缓冲 | 可视范围带 overscan 和运动缓冲；动画 delta 有上限，挂起恢复仍需媒体时间校准 | [layout][M-LAYOUT]、[常量与原因策略][M-CONSTS] |

React 绑定自己用 RAF 调用视觉 `update`，并通过 prop effect 更新媒体时间；Core 要求宿主驱动与 React 自动循环是不同层次。[React 绑定][M-REACT]

#### 滚动、缩放与模糊

触摸超过任一轴 10px 后确认滚动意图，组件自行维护偏移、速度、边界和惯性；手指直接控制时可以 snap，避免弹簧跟随滞后。滚轮无输入 150ms 后结束交互。自动归位的 500ms 只是允许条件，还需要焦点等条件满足，不能写成固定 500ms 后无条件抢回。[滚动控制][M-SCROLL]、[触发布局与归位][M-BASE]

普通播放的交错布局累计延迟从 0 开始，逐行延迟增量初始为 50ms，焦点之后还会衰减；seek、配置变化或连续手势走不同策略。正常滚动弹簧按相邻歌词时间间隔映射；seek / 间奏与结束状态另有参数。[原因策略][M-CONSTS]、[弹簧选择][M-SPRING]

播放时非激活主行缩放到 `0.97`、非激活背景行到 `0.75`，激活值为 `1`，暂停状态另行处理。模糊存在焦点行、触摸中、视口外等例外，DOM 最终 CSS blur 还会封顶到 5px；这些参数与 LB 的原生译文分别保留。[缩放状态][M-GROUP]、[模糊计算][M-BASE]、[最终样式][M-DOM-GROUP]

#### 逐词擦亮、长音与亮度

| 层 | 实际做法 | 代码入口 |
| --- | --- | --- |
| 几何与缓存 | 测量词宽、内边距和换行；按时间、尺寸、渐变宽度等签名缓存时间线 | [lyric-line][M-LINE-DOM] |
| Web Animations 遮罩 | 固定渐变 mask，预计算 mask-position 关键帧，保留词间停顿；seek 时重新定位动画时间 | [animator-web][M-MASK-WEB] |
| CSS 备用路径 | 用 CSS 变量与 calc / clamp 推进时间，需要逐帧写变量 | [animator-calc][M-MASK-CALC] |
| 行级明暗 | 亮层保留逐词 mask，暗层为副本；用 opacity 交叉淡化，配合 plus-lighter 合成 | [亮度控制][M-BRIGHTNESS]、[CSS][M-CSS] |
| 长音强调 | 独立于遮罩的逐字符缩放、位移和辉光关键帧；持续时间影响幅度 | [emphasize][M-EMPHASIZE] |

强调资格还有文本条件：CJK 词时长至少 1 秒；非 CJK 还要求 trim 后长度为 2–7，不能只沿用简写注释。[条件代码][M-LINE-BASE]

数据优化选项可主动调整起唱时间，包含最多提前 600ms 等策略；它们是 AMLL 的演出选择，不是 Apple 精确同步规则。模型还存在一个主行对应一个背景声部行的限制，不能当作任意多声部引擎。[选项与限制][M-INTERFACES]

### 2.3 共享的数据与显示边界

**综合建议**：把下面几层分别实现，便于替换渲染方案与对照各来源。

| 层 | 输入 / 输出 | 需要保持的边界 |
| --- | --- | --- |
| 歌词获取 | 来源能力 → 原始歌词 | 网络、认证和缓存由所属平台管理 |
| 格式解析 | 原始格式 → 通用歌词模型 | 标注不支持或缺失的字段，保留原时间信息 |
| 时间计算 | 播放时钟 + 歌词 → 当前行、当前词、进度 | seek、暂停和恢复后可从绝对时间重算 |
| 排版 | 文本、字体、宽度、方向 → 行词几何 | 重新排版不改变歌词身份与时间戳 |
| 视觉状态 | 时间结果 + 交互 → 位置、亮度、模糊、缩放 | 把视觉补间与播放时间分开 |
| 渲染 | 几何与状态 → UIKit / SwiftUI / Web / GPU | 各算法保留独立参数，不强行共用同一组常量 |

时间建议使用音频播放器提供的时钟。定时器或显示刷新只用于触发采样与重绘；seek 后直接根据新时间更新状态，不能依靠累计帧数推算歌词进度。这是工程建议，不能反向标成 Apple 的实现。

## 3. 背景：分别保留渲染路径

### 3.1 AW：网页交付代码分析

**作者记录**：作者先尝试调试 macOS Music，后来分析 Apple Music Web 的压缩 JavaScript，识别 Pixi.js 与相关滤镜，提取出 `LyricsScene` 的核心逻辑。文章描述的关键步骤是多份封面叠加、运动、扭曲、模糊及增强饱和度；作者明确指出它与原生背景存在差异。[分析文章][AW]

**源码可见**：[固定提交的 `bundle.ts`][AW-CODE] 使用四张封面副本。边长按视口宽度的 `1.25`、`0.8`、`0.5`、`0.25` 设置；两张较大副本原地旋转，两张较小副本同时沿轨迹移动。

这个文件应当作为一个独立版本记录：它已经包含作者的修改，不能直接当作 Apple 网页原始脚本。模糊、帧率、减少动态效果等差异见第 7 节。

同仓库还要分别阅读 [演示工程 `LyricsScene.ts`][AW-DEMO] 与文章链接的 [sandbox bundle][AW-SANDBOX]。后者公开副本的 `filters` 已置为空数组；本次没有校验它与某日期 Apple 线上文件的字节一致性。三份文件的行为不能互相代替。

### 3.2 LB：原生背景研究线索

LB 作者记录了 metallib 提取、渲染分析和模糊相关 hook；这可以作为继续研究原生渲染的入口。其 macOS `MusicFreeBlur` 示例针对另一个平台和版本，不能据此认定 iPadOS 16.4 与当前 iOS 的背景管线相同。[幕后记录][LB]

### 3.3 AMLL：组件自己的背景实现

AMLL 的背景是独立实现，不能把它的滤镜、插值方式或默认帧率直接写成 Apple 参数。该固定提交[实际导出四种 renderer][M-BG-EXPORT]，应分别记录：

| renderer | 主要路径 | 特定限制 / 差异 |
| --- | --- | --- |
| [PixiRenderer][M-BG-PIXI] | 四张封面 Sprite、多级 BlurFilter、颜色矩阵和双 BulgePinchFilter；新旧 container 透明度过渡 | 不是 AW 的 TwistFilter；低频音量 / hasLyric 接口为 NOOP；默认上限 30FPS |
| [MeshGradientRenderer][M-BG-MESH] | 封面降到 32×32 后增强颜色、多轮预模糊；控制点生成变形网格，shader 动态旋转 / 缩放 UV | 并非逐帧在 CPU 更新所有控制点；默认上限 60FPS；低频输入参与 shader |
| [IsolationRenderer][M-BG-ISOLATION] | 从封面提取四个主色，OkLab 调色板过渡后程序化着色 | 不采样完整封面纹理；调色板换图过渡 1000ms |
| [TitaniumRenderer][M-BG-TITANIUM] | 主题色、解析高度场和哈希沙粒的金属流沙效果 | 项目自有风格；不能当成 Apple 现有背景的逆向发现；默认 30FPS |

Mesh 的预模糊在 [img.ts][M-BG-IMG] 中是多轮水平 / 垂直滑动平均，不能称作每帧 GPU Gaussian。它通过递增 request ID、AbortController 和有效性检查处理异步换图，并包含 context lost / restore、暂停和资源清理路径；本次只做静态阅读，没有证明所有错误路径无泄漏。[Mesh 生命周期][M-BG-MESH]

共用 [base][M-BG-BASE] 管理尺寸、devicePixelRatio 与 renderScale；实际方法效果取决于 renderer，接口存在不代表每种 renderer 都实现了它。文档与默认值的差异列于 7.2。

### 3.4 FG：原生替代方案

**源码可见**：SwiftUI 包装平台 view，由 base / highlight 两组图层承载 radial `CAGradientLayer` blobs；highlight 设置 overlay compositing filter。颜色由调用方传入，库本身不从封面取色。[图层组织][FG-VIEW]、[blob 实现][FG-BLOB]

| 项目 | FG 快照中的实现 |
| --- | --- |
| 默认参数 | `highlights = []`、`speed = 1`、`blur = 0.75` |
| 实际模糊半径 | `pow(min(width, height), blur)`；`0.75` 是指数，不是固定半径 |
| 目标更新 | 每个 blob 独立定时，间隔 `0.8/speed...1.2/speed`，随机中心与尺寸 |
| 运动 | `CASpringAnimation`；mass `10/speed`、damping `50`、duration `1/speed`；起点读取 presentation layer |
| 暂停限制 | `speed <= 0` 停止调度；不能据此认定已提交的 CAAnimation 立即冻结 |

默认值和模糊公式见 [SwiftUI 包装][FG-WRAPPER]，调度与运动见 [view][FG-VIEW] 和 [blob][FG-BLOB]。透明度动画未显式设置 keyPath；其实际效果未经本次运行验证。macOS 对窗口可见性有处理，不能据此声称 iOS 已具备等价的 scenePhase 暂停逻辑。

### 3.5 SP：Metal 颜色控制点

**源码可见**：SP 在封面取色后，使用最多 8 个颜色控制点，由 Metal `colorEffect` 按距离权重混色。shader 参数为 `bias = 0.05`、`power = 2.5`、`noise = 2`；各点权重与 `alpha / (bias + distance^power)` 相关。它没有把完整封面作为旋转纹理。[shader][SP-SHADER]、[调用参数][SP-GRADIENT]

控制点以 20 秒 linear 动画向新位置插值，每 18 秒更新目标；该重叠时序按源码保留。颜色来自样例自带的 dominant-color 流程，不是已证实的 Apple 调色算法。[背景状态][SP-BACKGROUND-MODEL]、[控制点动画][SP-POINT]、[取色][SP-COLORS]

### 3.6 背景方案对照

| 路径 | 图形输入 | 主要运算 | 时间来源 / 已知边界 |
| --- | --- | --- | --- |
| LB 作者原生研究 | 原生渲染对象 / 二进制 | metallib 与模糊相关路径分析 | 公开材料不足以复现完整管线 |
| AW 重建 | 四张完整封面副本 | 旋转 / 位移 → twist → blur → saturation | ticker 的 `deltaMS`；不是音频节拍输入 |
| AMLL | 封面及组件设置 | 依具体 renderer 而定 | 不同 renderer 分别阅读，不统一成 AW 算法 |
| SP | 封面提取出的颜色 | 8 点距离权重混色与扰动 | 长周期插值与定时重设目标 |
| FG | 调用方提供的颜色 | radial blobs → 图层合成 → blur | 独立 timer 与 CA spring |

这几种路径有不同的输入和参数含义。选择其中一种实现，并不构成对其他方案或 Apple 原生算法的证明。

## 4. 队列与侧滑操作

### 4.1 RQ 的观察链

**作者记录**：从歌曲侧滑操作开始，检查视图层级、响应者、集合视图代理和方法地址，再结合断点、反汇编及调用栈追踪后续操作。笔记出现 `MusicApplication.SongsViewController`、`NowPlayingQueueViewController`、`UISwipeActionsConfiguration` 与 `MediaPlaybackCore` 等对象或模块。[原文][RQ]

记录中的侧滑配置同时包含 Next / Last 操作及 full-swipe 标志；后续日志还出现 `_MPCPlayerInsertItemsCommand`、`MPCMediaRemoteController`。拖动重排则出现集合视图 data source 的移动回调和 `_MPCPlayerReorderItemsCommand`。这是局部日志中的观察，不是完整的端到端命令规范。[日志与符号定位][RQ]

这些记录支持“从具体交互定位处理入口”的研究方法，但没有提供完整可复用的队列实现。作者对包装函数主要执行内存管理等解释仍使用猜测语气；不要将它升级为已确认结论。文中未明确被测 iOS 构建号，不为其补填 LB 的 16.4。

### 4.2 可抽象的前端契约

**综合建议**：把队列行为明确表达为操作，例如“紧接当前歌曲插入”“追加到尾部”“移动指定条目”。显示层提交意图，队列服务负责校验并发布结果。

| 问题 | 建议明确的语义 |
| --- | --- |
| 同一首歌多次出现 | 使用队列条目身份区分，不只使用歌曲 ID |
| 多来源歌曲 | 操作使用稳定来源与条目身份，不按名称或来源顺序猜测 |
| 拖动时队列发生变化 | 根据条目身份重新校验，处理目标已删除等情况 |
| 不可播放或来源停用 | 明确显示不可用状态，不改由其他平台处理 |
| 插入与重排 | 分开定义，不把动画中的临时顺序直接当成持久化结果 |

以上为落地建议，并非对 RQ 未完成部分的补全或对 Apple 队列服务的描述。

## 5. 播放器展开、收起与手势

SP 提供 SwiftUI 的 Now Playing 卡片动画和转场复刻，可用于补充研究原生界面表达方式。它不提供 Apple 内部控件或动画参数的证据。[项目入口][SP]

### 5.1 SP 的实际转场组合

**源码可见**：展开状态在同一 `ZStack` 中协调紧凑 / 完整播放器，使用共享 namespace 与封面 `matchedGeometryEffect`，控制区从底部进入。展开动画为 `.smooth(duration: 0.3, extraBounce: 0)`。[卡片实现][SP-EXPAND]

下拉手势使用 `UIGestureRecognizerRepresentable` 包装 `UIPanGestureRecognizer`。源码计算非负下拉量 `t` 和 `clamp(t / height, 0...1)`；结束时采用判据 `t + velocityY / 5 > height * 0.3`，否则回弹。取消状态未在结束分支中单独排除，移植前需要实际验证取消行为。[手势包装][SP-PAN]、[处理逻辑][SP-EXPAND]

样例还有独立透明 `UIWindow` / `UIHostingController` 及底层窗口 transform，不能将整个效果简化成一个 matched-geometry 动画。触摸穿透按 iOS 18 / 26 分支处理，部分判断依赖图层名称；这属于样例方案，不是本文推荐的通用窗口契约。[overlay 实现][SP-OVERLAY]

### 5.2 SP 的弹性滑条

拖动时按初始值加水平位移计算数值，将超界拉伸与被夹紧的业务值分开；拉伸同时影响长度和厚度。默认 active / inactive 高度为 `17/7`，growth / maxStretch 为 `9/9`，stretchNarrowing 为 `4`，push / pull 比率为 `0.2/0.5`。活动状态使用 smooth 动画，边界可触发触觉反馈。[逻辑与默认值][SP-SLIDER]

这些是作者复刻参数。样例的 `Player.play/stop` 只打印日志，没有提供真实音频播放、账号或完整媒体会话。[Player.swift][SP-PLAYER]

### 5.3 落地检查维度

实现时建议分别记录：起止几何、共享封面身份、展开进度、拖动偏移、背景与控件的插值、结束阈值及取消后的恢复。这里的检查维度属于**综合建议**；应和 SP 实际使用的状态、手势与动画分开阅读。

## 6. 对 NeoDizzy 的适用边界

本节只给出**综合建议**，不改变当前实现，也不提出新增 Apple Music 平台的要求。项目规范以 [AGENTS.md](../AGENTS.md) 和 [模块文档](modules.md) 为准。

- 歌词排版、逐词显示、背景和播放器转场可属于来源无关的共享视觉能力。
- 平台负责歌词请求、账号、凭据、网络任务及平台缓存，通过公开契约提供通用数据。
- 视觉组件不得直接引用某个平台的服务、账号或具体模型；不支持逐词时间时明确降级到逐行或纯文本。
- 来源、账号或会话变化后，迟到的歌词和封面结果不能覆盖当前曲目；异步结果须检查所属身份。
- 本地歌词与用户文件保留独立可用性；停用在线平台不应连带删除本地资料。
- 对照方案保持各自参数空间，例如“封面纹理扭曲”和“颜色图层渐变”不能只靠替换同一组参数互相转换。

## 7. 冲突与差异登记

本节保留相互冲突的说法、默认值与代码路径，不选择一个覆盖其他项。不同系统、不同版本或不同项目间的差异，也不自动解释为某一方有误。

| 编号 | 主题 | 方案 / 说法 A | 方案 / 说法 B | 使用方式 |
| --- | --- | --- | --- | --- |
| C01 | AW 模糊 | 文章分析 Apple Web 的 Kawase 模糊 | 固定 `bundle.ts` 激活 `BlurFilter`，Kawase 调用被注释 | 分别记为网页分析与作者重建版本，不合并 |
| C02 | AW 帧率 | 文章展示的脚本片段设置 `maxFPS = 15` | 重建文件未设置同一上限，使用 `deltaMS / 33.333333` 缩放运动 | 运动时间归一化不等于渲染帧率限制 |
| C03 | 背景输入 | AW 重建使用完整封面纹理 | FG 使用颜色与渐变图层 | 作为两种算法分别实现、比较 |
| C04 | 目标一致性 | LB 作者强调参数逆向后的还原度 | AMLL 明确目标不是完全模仿 | 不把两者的参数或质量声明当成同一标准 |
| C05 | 队列版本 | RQ 研究旧版队列行为 | 作者称 iOS 18 已调整行为，因此停止项目 | 不用旧版记录推断新版交互或内部函数 |
| C06 | LB 选中行位置 | 属性写 `.fraction(12)`，枚举只列 fraction / rect | 布局 / 预设出现 `.fixed(12)`、`.fixed(20)`、`.automatic`；builder 注释又称 fraction | 语义未统一，不能将 `12` 解释成比例或百分比 |
| C07 | LB 强调缩放范围 | 声明 `1...1` | builder `1...1.14` | 两值保留，未裁决 |
| C08 | LB glow 范围 | 声明 `0...0` | builder `0.4...30` | 两值保留，未裁决 |
| C09 | LB 渐变羽化 | 声明 / 布局 `30` | builder 写入 `40`，注释也保留两者 | 不给出唯一“原生值” |
| C10 | LB 字体内存偏移 | 前部估计为 `+184/+192/+200` | 后部布局 / builder 为 `+192/+200/+208` | 保留估计与后部版本；地址偏移不是公共 API |
| C11 | LB 语言方向 | 概述将 `fa` 与 `ja` 放在同一特殊路径 | 译文分支使 `fa` 返回 `leftToRight` | 视为译文内部疑点；`ja` 的 `topToBottom` 也只是作者命名，不能泛化 |
| C12 | LB helper 语义 | 初始化链注释把一些地址命名为歌词业务步骤 | 后部相同地址被命名为方向、释放对象或字典操作 | 两组解释均保留，不能依推测名称确定调用语义 |
| C13 | 背景混色 | SP 采用 Metal 颜色控制点，20 秒插值 / 18 秒换目标 | FG 采用 radial blobs，约 `0.8/speed...1.2/speed` 秒调度 spring | 输入、插值与调度均不同；参见 3.4–3.6 |
| C14 | FG blur 的含义 | 调用参数默认 `0.75` | 实际半径由画布最小边长的 `0.75` 次方计算 | 同时记录参数和公式，不能当固定 `0.75` 半径 |
| C15 | 停止动画 | FG 的 `speed <= 0` 停止新调度 | 已提交 CAAnimation 未被这条逻辑证明立即冻结 | 区分停止调度与冻结当前帧，不擅自宣称暂停效果 |

C06–C10 定位于 [LB][LB] 的 `code-specs` 属性、预设、布局与 builder；C11–C12 位于 `code-lyrics` 的概述、初始化链与相应函数。它们是公开译文内部的差异，尚不能确定来自翻译、整理、路径差别还是其他原因。本文没有擅自修正成一个可编译版本。

### 7.1 AW 各文件的差异：全部并列

下表区分作者[文章叙述][AW]、根目录 [A1：bundle.ts][AW-CODE]、同提交的 [A2：LyricsScene.ts][AW-DEMO]，以及另一提交的 [A3：sandbox/bundle.js][AW-SANDBOX]。A3 是有编辑痕迹的沙盒副本，不作为 Apple 原版文件取证。

| 主题 | 文章 / 研究叙述 | A1 根目录重建 | A2 演示工程 | A3 sandbox 副本 |
| --- | --- | --- | --- | --- |
| 模糊 | 原生段讨论 Gaussian，Web 段讨论 Kawase 近似 | 活跃 `BlurFilter(100,10,1,15)`；Kawase 全注释 | 五层 Kawase，强度 `5/10/20/40/80`，quality `1/1/2/2/2` | 保留滤镜配置，但实际 `filters = []` |
| 帧率上限 | 展示 `maxFPS = 15` | 没有显式同值限制 | 没有显式同值限制 | `maxFPS = 15` |
| powerPreference | 展示 `low-power` | 没有设置 | 设置 `low-power` | 设置 `low-power` |
| 减少动态效果 | 展示查询创建 | 仅声明字段，未赋值 / 消费 | 未见相应查询 | 创建查询；所读尾段未见消费 |
| 换封面 | 非完整集成规范 | 仅构造时传入 | 继承几何 / 角度后替换，没有交叉淡化 | 保留旧层渐隐逻辑 |
| 小图旋转 / 轨道 | 说明两张小图运动 | 直接更新 rotation 并用于轨道计算 | 同 A1 的直接方式 | 独立角数组驱动轨道，显示 rotation 取负值 |
| 清理 | 没有生产完备性承诺 | 没有 destroy 方法 | `app.destroy(false)` | `destroy(true, {children/texture/baseTexture: true})` |
| Pixi 版本 | 作者匹配为 `7.4.2` | 根 [package.json][AW-PACKAGE] 声明 `^7.4.3` | 依各工程依赖另行核对 | 不能据作者匹配结论证明副本完整性 |

减少动态效果“创建查询”与“实际响应设置”是两件事。A1 的 `deltaMS / 33.333333` 也只是运动步长归一化，不能推出 30FPS 渲染上限。本文没有把上述版本拼成一个修正后的“苹果算法”。

### 7.2 AMLL 的实现与说明差异

| 主题 | 一处说明 / 实现 | 另一处说明 / 实现 | 保留方式 |
| --- | --- | --- | --- |
| renderer 数量 | [背景指南][M-BG-DOC] 列 Mesh / Pixi 两种 | [实际导出][M-BG-EXPORT] 包含 Mesh / Pixi / Isolation / Titanium | 文档范围与实际快照同时记录 |
| flowSpeed | [base 接口注释][M-BG-BASE] 写默认 `8` | 实例字段为 `1` | 不选出全库统一默认值 |
| renderScale | 同处注释写默认 `0.5` | 实例字段为 `0.75` | 注释值与字段值并列 |
| 默认 FPS | 共用注释写 `30` | Mesh 为 `60`；Pixi / Titanium 为 `30` | 按 renderer 记录 |
| Pixi 轨道 | AW 使用 sin / cos 的环绕轨迹 | [AMLL Pixi][M-BG-PIXI] 的两张小图 x / y 都有 cos 项，且末层余弦项没有整体乘圆半径 | 如实保留公式差别，不擅自修成圆轨道 |
| 低频平滑 | [Mesh][M-BG-MESH] 计算 smoothedVolume | 所读绘制 uniform 使用 `this.volume` | 不只凭字段名声称最终用了平滑量 |
| 长音资格 | 注释简写长度不超过 7 | [实际条件][M-LINE-BASE] 区分 CJK 与非 CJK，后者还有最小长度 2 | 注释与分支分别保留 |
| 自动归位 | [scroll][M-SCROLL] 提供 500ms 允许条件 | [base][M-BASE] 还要求焦点等条件满足 | 不缩写成固定超时归位 |
| UI 缩放 | LB 未选中缩放候选包含 `0.98` / 声部 `0.9` | [AMLL group][M-GROUP] 主行 / 背景行采用 `0.97` / `0.75` 等状态 | 属于不同实现的参数，不互相覆盖 |
| 生产成熟度 | 项目功能与示例较丰富 | [Core README][M-CORE] 仍标未完成开发，主 README 招募维护者 | 同时保留，本文没有生产稳定性实测 |

上述差异可能是版本演进、文档滞后、独立设计或实现问题。本次没有足够运行证据给出统一归因。

## 8. 后续实现与验证清单

以下项目是未来验收要求，**本次均未执行**。阅读源码和整理文档不等于通过这些检查。

| 范围 | 需要观察的场景 |
| --- | --- |
| 歌词时间 | 暂停 / 恢复、快进后退、跳入句中、连续 seek、切歌 |
| 排版 | 多行换行、长词、空行、译文、和声、RTL、混合语言、动态字体 |
| 手动滚动 | 脱离自动跟随、恢复跟随、拖动期间歌词跨行、点行跳转 |
| 背景 | 无封面、方形 / 非方形封面、换图、旋转、窗口变化、暂停及减少动态效果 |
| 转场 | 慢拖、快速甩动、取消、中途旋转、展开时切歌、无障碍操作 |
| 多来源 | 来源停用、账号切换、旧请求返回、本地曲目、缺失歌词能力 |
| 性能 | 真机帧耗时、CPU / GPU、内存、长歌词、发热与后台恢复 |

对照时应记录系统与设备、源码提交、输入歌曲 / 歌词、屏幕尺寸、字体及参数。评价指标分为“与目标版本的差异”和“自身是否稳定正确”，分别报告。

## 9. 引用与复用说明

本文采用摘要、结构说明和代码入口，不收录完整反编译译文、原始二进制、着色器或账号调试数据。公开代码、闭源发行材料和研究译文的许可分别记录，不把公开可访问等同于可任意复用。

| 来源 | 本次确认的许可 / 范围 |
| --- | --- |
| LB | 项目为 proprietary；幕后页将公开译文限制为研究参考、禁止商业用途，代码头保留全部权利 |
| RQ | 研究文章；本文未确认其存在可直接移植的独立代码许可 |
| AW | 所读固定 tree 未见根 LICENSE；不标成 MIT；具体文件及依赖分别核对 |
| AMLL | [core package][M-PACKAGE] 标注 `AGPL-3.0-only`；局部 MIT attribution 不改变全库标记；本次未评估与 NeoDizzy 的许可兼容性 |
| SP / FG | 两个固定快照均为 MIT；见各自 [SP LICENSE][SP-LICENSE] / [FG LICENSE][FG-LICENSE] |

尚未覆盖：Apple Music 完整导航、全部业务页面、系统媒体集成、音频服务、服务端协议及当前各系统版本的完整前端实现。本文没有将局部观察外推为这些范围的结论。

[LB]: https://lyricsblossom.theoscarshen.com/behind-the-scenes
[LB-REPO]: https://github.com/Eplorr/LyricsBlossom
[RQ]: https://www.rahul.ws/blog/re-apple-music
[AW]: https://www.aadishv.dev/music
[AW-CODE]: https://github.com/aadishv/html-music/blob/4ef618ea2638a0c435d23f182f7aa10e30757ef6/bundle.ts
[AMLL]: https://github.com/amll-dev/applemusic-like-lyrics
[AMLL-README]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/README-CN.md
[SP]: https://github.com/f728743/AppleMusicStylePlayer
[FG]: https://github.com/Cindori/FluidGradient
[SP-EXPAND]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/NowPlaying/ExpandableNowPlaying.swift
[SP-PAN]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/PanGesture.swift
[SP-OVERLAY]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/UniversalOverlay.swift
[SP-SLIDER]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/Components/ElasticSlider.swift
[SP-PLAYER]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/Player/Player.swift
[SP-SHADER]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/Components/Background/MulticolorGradientShader.metal
[SP-GRADIENT]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/Components/Background/MulticolorGradient.swift
[SP-BACKGROUND-MODEL]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/Components/Background/ColorfulBackgroundModel.swift
[SP-POINT]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/Components/Background/ColorPoint.swift
[SP-COLORS]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/AppleMusicStylePlayer/UI/DominantColors.swift
[SP-LICENSE]: https://github.com/f728743/AppleMusicStylePlayer/blob/a0b5631417dec05d092c3c61df4679ed361743bf/LICENSE
[FG-WRAPPER]: https://github.com/Cindori/FluidGradient/blob/9ddda4cf23671ef0228e88681ec6210cb3e0d7f7/Sources/FluidGradient/FluidGradient.swift
[FG-VIEW]: https://github.com/Cindori/FluidGradient/blob/9ddda4cf23671ef0228e88681ec6210cb3e0d7f7/Sources/FluidGradient/FluidGradientView.swift
[FG-BLOB]: https://github.com/Cindori/FluidGradient/blob/9ddda4cf23671ef0228e88681ec6210cb3e0d7f7/Sources/FluidGradient/BlobLayer.swift
[FG-LICENSE]: https://github.com/Cindori/FluidGradient/blob/9ddda4cf23671ef0228e88681ec6210cb3e0d7f7/LICENSE
[AW-DEMO]: https://github.com/aadishv/html-music/blob/4ef618ea2638a0c435d23f182f7aa10e30757ef6/music-demo/src/LyricsScene.ts
[AW-SANDBOX]: https://github.com/aadishv/html-music/blob/e9d8026e5c823e3782dee453654b5de1e2f34655/sandbox/bundle.js
[AW-PACKAGE]: https://github.com/aadishv/html-music/blob/4ef618ea2638a0c435d23f182f7aa10e30757ef6/package.json
[M-CORE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/README-CN.md
[M-INTERFACES]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/interfaces.ts
[M-BASE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/index.ts
[M-DOM]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/index.ts
[M-SEEK]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/seek-detector.ts
[M-TIMELINE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/timeline.ts
[M-LAYOUT]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/layout.ts
[M-CONSTS]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/consts.ts
[M-REACT]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/react/src/lyric-player.tsx
[M-SCROLL]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/scroll.ts
[M-SPRING]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/spring.ts
[M-GROUP]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/group.ts
[M-DOM-GROUP]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/lyric-group.ts
[M-LINE-DOM]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/lyric-line.ts
[M-MASK-WEB]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/animation/mask/animator-web.ts
[M-MASK-CALC]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/animation/mask/animator-calc.ts
[M-BRIGHTNESS]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/line-brightness.ts
[M-CSS]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/styles/lyric-player.module.css
[M-EMPHASIZE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/dom/animation/emphasize/index.ts
[M-LINE-BASE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/lyric-player/base/line.ts
[M-BG-EXPORT]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/index.ts
[M-BG-BASE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/base.ts
[M-BG-DOC]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/docs/src/content/docs/guides/component/background.md
[M-BG-PIXI]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/pixi-renderer.ts
[M-BG-MESH]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/mesh-renderer/index.ts
[M-BG-IMG]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/img.ts
[M-BG-ISOLATION]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/isolation/index.ts
[M-BG-TITANIUM]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/src/bg-render/titanium/index.ts
[M-PACKAGE]: https://github.com/amll-dev/applemusic-like-lyrics/blob/5fee356362353dbb24ce9bea3a62536478040de7/packages/core/package.json
