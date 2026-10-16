import SwiftUI

/// 统一搜索里一个来源的分组标题：来源名称，有更多结果时右侧是「查看全部」。
/// 「查看全部」走导航路径（`AppRoute`），在全部结果页里再点进详情时只推入一页。
struct SearchSectionHeader: View {
    let title: String
    var allResults: AppRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer()
            if let allResults {
                NavigationLink("查看全部", value: allResults).font(.subheadline)
            }
        }
    }
}

/// 分组里的一句说明：没有结果、正在搜索。
struct SearchSectionMessage: View {
    let text: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading { ProgressView().controlSize(.small) }
            Text(text).font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// 一个来源搜索失败：只影响这一组，带重试。
struct SearchSectionFailure: View {
    let title: String
    let message: String
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DizzyPalette.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("重试") { Task { await retry() } }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(14)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
    }
}
