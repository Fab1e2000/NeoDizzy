import SwiftUI
import Combine

/// 关注动态：已关注社团的新作，按社团分组。需要有效的 token。
@Observable
final class FeedModel {
    private(set) var userID: Int?
    private(set) var groups: PagedList<FeedGroup>?

    func update(userID: Int?) {
        guard userID != self.userID else { return }
        self.userID = userID
        groups = userID.map { _ in PagedList { page in try await DizzyAPI.shared.feed(page: page) } }
    }
}

struct FeedView: View {
    @Environment(AccountStore.self) private var account
    @State private var model = FeedModel()

    var body: some View {
        MainTabPage(tab: .feed, onRefresh: { await model.groups?.reload() }) {
            if account.isLoggedIn, !account.isSessionExpired, let groups = model.groups {
                PagedContent(list: groups, webURL: DizzyURL.page("/feed/"), emptyMessage: "关注的社团还没有发布新作。") { groups in
                    ForEach(groups) { group in
                        FeedGroupSection(group: group)
                    }
                }
            } else {
                LoginPrompt(systemImage: "newspaper.fill", message: "登录后，你关注的社团发布的新作会显示在这里。")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyFollowingDidChange)) { _ in
            Task { await model.groups?.reload() }
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.update(userID: userID)
        }
        .onChange(of: account.isSessionExpired) { _, isExpired in
            // 重新登录后 token 换了，重新加载。
            if !isExpired { Task { await model.groups?.reload() } }
        }
    }
}

/// 关注动态只展示社团信息；点击后在社团详情查看作品。
private struct FeedGroupSection: View {
    let group: FeedGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: AppRoute.label(name: group.labelName)) {
                HStack(spacing: 10) {
                    ArtworkImage(url: group.labelCoverURL, cornerRadius: 18)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.labelName)
                            .font(.headline)
                            .foregroundStyle(DizzyPalette.text)
                            .lineLimit(1)
                        if let date = group.addDate.flatMap(Self.displayDate) {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DizzyPalette.mutedText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    /// `2026-09-04T11:00:11.375Z` → 本地时区的 `2026-09-04`，和页面上其他日期写法一致，不随系统语言变化。
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
