import Combine
import SwiftUI

/// 关注动态：已关注社团的新作，每个社团只显示一次，点击进入社团页。
struct FeedPage: View {
    @Environment(MacAppModel.self) private var model
    @Environment(AccountStore.self) private var account

    var body: some View {
        PageScroll(title: String(localized: "关注")) {
            if account.isLoggedIn, !account.isSessionExpired, let groups = model.feed.groups {
                PagedSection(list: groups, webURL: DizzyURL.page("/feed/"), emptyTitle: "关注的社团还没有发布新作",
                             emptySystemImage: "newspaper") { groups in
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 22, alignment: .top)],
                              alignment: .leading, spacing: 26) {
                        ForEach(groups) { FeedLabelCard(group: $0) }
                    }
                }
            } else {
                LoginPromptView(systemImage: "newspaper", message: "登录后，你关注的社团发布的新作会显示在这里。")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyFollowingDidChange)) { _ in
            Task { await model.feed.groups?.reload() }
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.feed.update(userID: userID)
        }
        .onChange(of: account.isSessionExpired) { _, isExpired in
            if !isExpired { Task { await model.feed.groups?.reload() } }
        }
        .pageRefresh { await model.feed.groups?.reload() }
    }
}

/// 关注页里的一个社团：圆形头像、名称与最近更新日期，与 Music 的艺人网格相同。
private struct FeedLabelCard: View {
    let group: FeedGroup
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: AppRoute.label(name: group.labelName)) {
            VStack(spacing: 8) {
                ArtworkImage(url: group.labelCoverURL, cornerRadius: 999)
                    .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 10 : 5, y: 3)
                    .scaleEffect(isHovering ? 1.02 : 1)
                Text(group.labelName).font(.body.weight(.medium)).lineLimit(1)
                if let date = group.addDate.flatMap(Self.displayDate) {
                    Text("更新于 \(date)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.snappy(duration: 0.18)) { isHovering = hovering } }
    }

    /// `2026-09-04T11:00:11.375Z` → 本地时区的 `2026-09-04`。
    nonisolated private static func displayDate(_ text: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
