import SwiftUI

enum PageMetrics {
    /// 内容区左右留白，与 Music 的页面边距接近。
    static let margin: CGFloat = 28
    static let gridColumns = [GridItem(.adaptive(minimum: 158, maximum: 230), spacing: 22, alignment: .top)]
    static let gridSpacing: CGFloat = 26
}

extension Font {
    /// 页面大标题（Music 的「主页」「专辑」等）。
    static let pageTitle = Font.system(size: 28, weight: .bold)
    /// 分区标题。
    static let sectionTitle = Font.system(size: 19, weight: .bold)
}

/// 标准页面：可滚动内容，顶部大标题。大标题写在内容里，窗口标题栏不显示标题，与 Music 一致。
struct PageScroll<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let title {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.pageTitle)
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                content
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title ?? "")
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
        case .price, .deal: .dizzyGold
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
            .foregroundStyle(prominent ? Color.dizzyGold : .secondary)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(prominent ? Color.dizzyGold : .secondary, lineWidth: 0.8))
    }
}

/// 圆形头像（社团、用户）。
struct AvatarImage: View {
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        ArtworkImage(url: url, cornerRadius: size / 2)
            .frame(width: size, height: size)
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
