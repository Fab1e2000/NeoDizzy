import SwiftUI

/// Loaded on demand so local albums remain usable without making community requests.
struct DiscCommunityView: View {
    let discID: String
    @Environment(AccountStore.self) private var account
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { expanded.toggle() } label: {
                HStack {
                    Label("社区 · +dB / 短评 / repo", systemImage: "bubble.left.and.bubble.right")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.font(.headline)
            }.buttonStyle(.plain)
            if expanded {
                DiscCommunityContent(discID: discID)
                    .id("\(discID)-\(account.account?.userID ?? 0)-\(account.isSessionExpired)")
            }
        }
        .padding(16)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 16))
    }
}
struct DiscCommunityContent: View {
    @Environment(AccountStore.self) private var account
    @State private var model: DiscCommunityModel
    @State private var draft = ""
    @State private var deleting = false
    @State private var showReviews = false
    init(discID: String) { _model = State(initialValue: DiscCommunityModel(discID: discID)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    guard let id = account.account?.userID, !account.isSessionExpired else { account.isLoginPresented = true; return }
                    Task { _ = await model.act { model.likes = try await DizzyCommunity.shared.toggleLike(model.discID, userID: id) } }
                } label: {
                    Label(model.likes.map { "+\($0.likes * 2) dB" } ?? "+2 dB", systemImage: model.likes?.ilikethis == true ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(model.likes?.ilikethis == true ? "取消点赞" : "点赞，加 2 dB")
                .disabled(model.busy || !model.loaded)
                Spacer()
                Button { Task { await model.refresh(); await model.comments.reload(); await model.reviews.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.busy)
                    .accessibilityLabel("刷新社区")
            }
            if let failure = model.failure { Text(failure).font(.footnote).foregroundStyle(DizzyPalette.danger) }
            if !model.loaded && model.failure == nil { ProgressView() }
            if model.context?.myComment != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("我的短评").font(.subheadline.bold())
                    if let text = model.context?.myComment, !text.isEmpty { Text(text).font(.subheadline) }
                    Button("删除我的短评", role: .destructive) { deleting = true }.disabled(model.busy)
                }
            } else if model.context?.canComment == true {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("写一条短评（140 字以内）", text: $draft, axis: .vertical)
                        .lineLimit(3...6).padding(10)
                        .background(DizzyPalette.background, in: .rect(cornerRadius: 10))
                    HStack {
                        Text("\(draft.unicodeScalars.count) / 140").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                        Spacer()
                        Button("发表") {
                            guard let id = account.account?.userID else { account.isLoginPresented = true; return }
                            let text = draft
                            Task { if await model.act({ try await DizzyCommunity.shared.postComment(text, discID: model.discID, userID: id) }) { draft = "" } }
                        }.buttonStyle(.borderedProminent)
                            .disabled(model.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 140)
                    }
                }
            } else if !account.isLoggedIn || account.isSessionExpired || (model.loaded && model.context?.userID == nil) {
                Button("登录后点赞和发表短评") { account.isLoginPresented = true }
            }
            Picker("社区内容", selection: $showReviews) { Text("短评").tag(false); Text("repo 长评").tag(true) }.pickerStyle(.segmented)
            if showReviews {
                CommunityPagedContent(list: model.reviews, emptyMessage: "还没有 repo。") { reviews in
                    ForEach(reviews) { ReviewRow(review: $0) }
                }
            } else {
                CommunityPagedContent(list: model.comments, emptyMessage: "还没有短评。") { comments in
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            CommunityUserLink(user: comment.user)
                            Text(comment.text).font(.subheadline).textSelection(.enabled)
                            if let badge = comment.badge { Text(badge).font(.caption2).foregroundStyle(DizzyPalette.mutedText) }
                            Divider()
                        }
                    }
                }
            }
        }
        .task { await model.refresh() }
        .confirmationDialog("删除自己的短评？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除短评", role: .destructive) {
                guard let id = account.account?.userID else { return }
                Task { _ = await model.act { try await DizzyCommunity.shared.deleteComment(discID: model.discID, userID: id) } }
            }
        }
    }
}
struct CommunityUserLink: View {
    let user: CommunityUser
    var body: some View {
        NavigationLink(value: AppRoute.user(id: user.id)) {
            HStack(spacing: 10) {
                ArtworkImage(url: user.avatarURL, cornerRadius: 20).frame(width: 36, height: 36)
                Text(user.name).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.info)
            }
        }.buttonStyle(.plain)
    }
}
struct ReviewRow: View {
    let review: ReviewSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let user = review.user { CommunityUserLink(user: user) }
            NavigationLink(value: AppRoute.review(id: review.id)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(review.title).font(.headline)
                    if !review.excerpt.isEmpty { Text(review.excerpt).font(.subheadline).lineLimit(4).foregroundStyle(DizzyPalette.mutedText) }
                    if let date = review.date { Text(date).font(.caption).foregroundStyle(DizzyPalette.mutedText) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain)
            Divider()
        }
    }
}

/// Explicit paging inside the inline community card avoids eagerly loading every page.
private struct CommunityPagedContent<Item: Identifiable & Sendable, Content: View>: View {
    let list: PagedList<Item>
    let emptyMessage: String
    @ViewBuilder var content: ([Item]) -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content(list.items)
            if let failure = list.failure {
                Text(failure).font(.caption).foregroundStyle(DizzyPalette.danger)
                Button("重试") { Task { await list.loadMore() } }
            } else if list.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if list.isEmpty {
                Text(emptyMessage).font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
            } else if list.hasMore {
                Button("加载更多") { Task { await list.loadMore() } }.frame(maxWidth: .infinity)
            }
        }.task { if list.items.isEmpty { await list.loadMore() } }
    }
}
