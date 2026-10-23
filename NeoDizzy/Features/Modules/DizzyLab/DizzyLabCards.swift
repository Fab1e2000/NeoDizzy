import SwiftUI

/// 专辑卡片：封面、标题、社团和价格。
struct DiscCard: View {
    let disc: DiscSummary
    var showsLabel = true
    /// 额外的一行说明，例如限时优惠的截止日期。
    var caption: String?
    /// 横向陈列里所有卡片都占两行标题的高度，封面大小一致。
    var reservesTitleLines = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(url: disc.coverURL, cornerRadius: 10)
            Text(disc.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(2, reservesSpace: reservesTitleLines)
                .multilineTextAlignment(.leading)
            if showsLabel, let label = disc.labelName {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .lineLimit(1)
            }
            if disc.price != nil || disc.isHiRes {
                HStack(spacing: 6) {
                    if let price = disc.price { PriceText(price: price) }
                    if disc.isHiRes { HiResBadge() }
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .prefetchAlbumArtwork(url: disc.coverURL)
    }
}

/// 音质标记放在价格旁边，不遮挡封面。
struct HiResBadge: View {
    var body: some View {
        Text("Hi-Res")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DizzyPalette.mutedText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DizzyPalette.mutedText.opacity(0.6), lineWidth: 1))
    }
}

/// 价格：免费为绿色，兑换为蓝色，其余为网站的购买色；限时优惠带划掉的原价。
struct PriceText: View {
    let price: PriceTag

    var body: some View {
        HStack(spacing: 6) {
            if case .deal(let original, _) = price {
                Text(PriceTag.yuan(original))
                    .strikethrough()
                    .foregroundStyle(DizzyPalette.mutedText)
            }
            Text(price.text)
                .foregroundStyle(color)
        }
        .font(.caption.weight(.semibold))
    }

    private var color: Color {
        switch price {
        case .free: DizzyPalette.success
        case .redeem: DizzyPalette.info
        case .price, .deal: DizzyPalette.accent
        }
    }
}

/// 两列专辑网格，点击进入专辑页。
struct DiscGrid: View {
    let discs: [DiscSummary]
    var showsLabel = true

    var body: some View {
        LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
            ForEach(discs) { disc in
                NavigationLink(value: AppRoute.disc(id: disc.id)) {
                    DiscCard(disc: disc, showsLabel: showsLabel)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// pack 卡片，点击进入 pack 页。
struct PackCard: View {
    let pack: PackSummary

    var body: some View {
        NavigationLink(value: AppRoute.pack(id: pack.id)) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: pack.coverURL, cornerRadius: 10)
                Text(pack.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let label = pack.labelName {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(1)
                }
                if let price = pack.price {
                    PriceText(price: .price(price))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

