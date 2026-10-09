import SwiftUI

/// Mac 版统一的排版参数，各页面只引用这里的常量。
enum PageMetrics {
    /// 内容区左右留白。
    static let margin: CGFloat = 32
    /// 超宽窗口里内容不再继续拉伸，居中显示。
    static let maxContentWidth: CGFloat = 1400
    /// 页面内各分区之间的间距。
    static let sectionSpacing: CGFloat = 32
    static let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]
    static let gridSpacing: CGFloat = 28
    /// 社团、搜索结果等横向信息行组成的网格。
    static let rowColumns = [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]
    /// 网格卡片的封面固定按这个尺寸解码，窗口缩放时不重新解码。
    static let cardArtworkSize = CGSize(width: 400, height: 400)
    /// 底部播放条的高度，页面内容在它上方留出同样的空间。
    static let playerBarInset: CGFloat = 72
}

extension Font {
    /// 页面大标题（Music 的「主页」「专辑」等）。
    static let pageTitle = Font.system(size: 26, weight: .bold)
    /// 分区标题。
    static let sectionTitle = Font.system(size: 18, weight: .bold)
    /// 卡片与列表的标题、副标题。
    static let cardTitle = Font.system(size: 13, weight: .medium)
    static let cardSubtitle = Font.system(size: 13)
    /// 说明文字。
    static let note = Font.system(size: 12)
}

extension EnvironmentValues {
    /// 根页面所属的导航项，用来在切换导航项后恢复滚动位置。推入的页面为 nil。
    @Entry var pageScrollKey: NavigationItem?
}

/// 标准页面：可滚动内容，顶部大标题。大标题写在内容里，窗口标题栏不显示标题，与 Music 一致。
/// 页面自己的切换控件（分类、专辑 / 歌曲）放在标题右侧：工具栏正中留给顶部导航栏。
struct PageScroll<Content: View, Accessory: View>: View {
    var title: String?
    var subtitle: String?
    var accessory: Accessory
    var content: Content
    @Environment(\.pageScrollKey) private var scrollKey
    @Environment(MacAppModel.self) private var model
    @State private var position = ScrollPosition(edge: .top)

    init(title: String? = nil, subtitle: String? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PageMetrics.sectionSpacing) {
                if let title {
                    PageTitleRow(title: title, subtitle: subtitle) { accessory }
                }
                content
            }
            .pageContentFrame()
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
            if let scrollKey { model.scrollOffsets[scrollKey] = offset }
        }
        .onAppear {
            if let scrollKey, let offset = model.scrollOffsets[scrollKey], offset > 0 { position.scrollTo(y: offset) }
        }
        .navigationTitle(title ?? "")
    }
}

extension PageScroll where Accessory == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// 页面大标题，右侧可放页面自己的分段控件。
struct PageTitleRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.pageTitle)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension View {
    /// 统一的页边距与最大内容宽度。
    func pageContentFrame() -> some View {
        frame(maxWidth: PageMetrics.maxContentWidth, alignment: .leading)
            .padding(.horizontal, PageMetrics.margin)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// 分区标题，可在右侧放「查看全部」之类的操作。
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// 可折叠的长文本，默认显示前几行。
struct ExpandableText: View {
    let text: String
    var collapsedLines = 4
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : collapsedLines)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading)
            Button(isExpanded ? "收起" : "更多") {
                withAnimation(.snappy) { isExpanded.toggle() }
            }
            .buttonStyle(.link)
            .font(.callout.weight(.semibold))
        }
    }
}

/// 价格：免费为绿色，兑换为蓝色，其余为 DizzyLab 金色；限时优惠带划掉的原价。
struct PriceLabel: View {
    let price: PriceTag

    var body: some View {
        HStack(spacing: 5) {
            if case .deal(let original, _) = price {
                Text(PriceTag.yuan(original))
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            Text(price.text)
                .foregroundStyle(color)
        }
        .font(.callout.weight(.medium))
    }

    private var color: Color {
        switch price {
        case .free: DizzyPalette.success
        case .redeem: DizzyPalette.info
        case .price, .deal: .dizzyAccent
        }
    }
}

/// 封面角落和曲目旁的小标记：Hi-Res、试听。
struct TagBadge: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(prominent ? Color.dizzyAccent : .secondary)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(prominent ? Color.dizzyAccent : .secondary, lineWidth: 0.8))
    }
}

nonisolated enum TimeFormat {
    /// `3:07`，超过一小时为 `1:02:03`。
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// 专辑页脚的总时长：「42 分钟」「1 小时 5 分钟」。
    static func total(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(max(minutes, 1)) 分钟"
    }
}
