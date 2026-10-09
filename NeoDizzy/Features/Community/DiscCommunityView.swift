import SwiftUI

// MARK: - 专辑页里的社区预览

/// 专辑页底部的社区区块，参照 App Store 的「评分及评论」：
/// 标题行带「查看全部」，下面是 +dB 汇总和点赞按钮，再下面是可横向滑动的短评卡片。
/// 区块在 LazyVStack 里滚到附近才创建，本地专辑不会一打开就请求社区内容。
struct DiscCommunityView: View {
    let discID: String
    @Environment(AccountStore.self) private var account

    var body: some View {
        DiscCommunityPreview(discID: discID)
            // 换账号后重新读取「我的短评」和点赞状态。
            .id("\(discID)-\(account.account?.userID ?? 0)-\(account.isSessionExpired)")
    }
}

private struct DiscCommunityPreview: View {
    @State private var model: DiscCommunityModel
    @State private var isComposing = false
    @State private var isConfirmingDelete = false
    private static let previewLimit = 10

    init(discID: String) { _model = State(initialValue: DiscCommunityModel(discID: discID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: AppRoute.discCommunity(id: model.discID)) {
                HStack(alignment: .firstTextBaseline) {
                    Text("社区").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Text("查看全部").font(.subheadline).foregroundStyle(DizzyPalette.accent)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)

            DiscLikeSummary(model: model)
                .padding(.horizontal, 20)

            if let failure = model.failure {
                Text(failure).font(.footnote).foregroundStyle(DizzyPalette.danger).padding(.horizontal, 20)
            }

            commentCards

            DiscCommentComposeButton(model: model, isComposing: $isComposing, isConfirmingDelete: $isConfirmingDelete)
                .padding(.horizontal, 20)
        }
        .task {
            await model.refresh()
            if model.comments.items.isEmpty { await model.comments.loadMore() }
        }
        .discCommentComposer(model: model, isComposing: $isComposing, isConfirmingDelete: $isConfirmingDelete)
    }

    @ViewBuilder private var commentCards: some View {
        let comments = Array(model.comments.items.prefix(Self.previewLimit))
        let myComment = model.context?.myComment
        if comments.isEmpty && myComment == nil {
            Group {
                if model.comments.isLoading || !model.loaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                } else if model.comments.failure == nil {
                    Text("还没有短评，来写第一条吧。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    if let myComment {
                        DiscCommentCard(name: "我的短评", avatarURL: nil, badge: nil, text: myComment)
                    }
                    ForEach(comments) { comment in
                        NavigationLink(value: AppRoute.discCommunity(id: model.discID)) {
                            DiscCommentCard(name: comment.user.name, avatarURL: comment.user.avatarURL,
                                            badge: comment.badge, text: comment.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }
}

/// 一张短评卡片：宽度约为屏幕的八成，固定高度，正文最多四行。
private struct DiscCommentCard: View {
    let name: String
    let avatarURL: URL?
    let badge: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let avatarURL {
                    AvatarImage(url: avatarURL, size: 28)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(text)
                .font(.subheadline)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.82 }
        .frame(height: 158)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 点赞与撰写

/// +dB 汇总与点赞按钮：点赞一次加 2 dB，再点取消。
private struct DiscLikeSummary: View {
    let model: DiscCommunityModel
    @Environment(AccountStore.self) private var account

    private var isLiked: Bool { model.likes?.ilikethis == true }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.likes.map { "+\($0.likes * 2) dB" } ?? "+0 dB")
                    .font(.title.bold())
                    .contentTransition(.numericText())
                    .redacted(reason: model.likes == nil ? .placeholder : [])
                Text(model.likes.map { "\($0.likes) 人点赞" } ?? "点赞人数")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .redacted(reason: model.likes == nil ? .placeholder : [])
            }
            Spacer()
            Button(action: toggle) {
                Label(isLiked ? "已 +2 dB" : "+2 dB", systemImage: isLiked ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isLiked ? Color.pink : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(isLiked ? .pink : .primary)
            .disabled(model.busy || !model.loaded)
            .accessibilityLabel(isLiked ? "取消点赞" : "点赞，加 2 dB")
        }
        .animation(.snappy, value: model.likes?.likes)
    }

    private func toggle() {
        guard let id = account.account?.userID, !account.isSessionExpired else {
            account.isLoginPresented = true
            return
        }
        Task { _ = await model.act { model.likes = try await DizzyCommunity.shared.toggleLike(model.discID, userID: id) } }
    }
}

/// 「撰写短评」：已经写过时换成「删除我的短评」，未登录时提示登录。
private struct DiscCommentComposeButton: View {
    let model: DiscCommunityModel
    @Binding var isComposing: Bool
    @Binding var isConfirmingDelete: Bool
    @Environment(AccountStore.self) private var account

    var body: some View {
        if model.context?.myComment != nil {
            Button(role: .destructive) { isConfirmingDelete = true } label: {
                Label("删除我的短评", systemImage: "trash")
            }
            .font(.subheadline.weight(.semibold))
            .disabled(model.busy)
        } else if !account.isLoggedIn || account.isSessionExpired || (model.loaded && model.context?.userID == nil) {
            Button { account.isLoginPresented = true } label: {
                Label("登录后点赞和撰写短评", systemImage: "person.crop.circle")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DizzyPalette.accent)
        } else if model.context?.canComment == true {
            Button { isComposing = true } label: {
                Label("撰写短评", systemImage: "square.and.pencil")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DizzyPalette.accent)
        }
    }
}

private extension View {
    func discCommentComposer(model: DiscCommunityModel, isComposing: Binding<Bool>,
                             isConfirmingDelete: Binding<Bool>) -> some View {
        modifier(DiscCommentComposerModifier(model: model, isComposing: isComposing, isConfirmingDelete: isConfirmingDelete))
    }
}

private struct DiscCommentComposerModifier: ViewModifier {
    let model: DiscCommunityModel
    @Binding var isComposing: Bool
    @Binding var isConfirmingDelete: Bool
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isComposing) {
                DiscCommentComposer(model: model)
                    .restoringAppColorScheme()
            }
            .confirmationDialog("删除自己的短评？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("删除短评", role: .destructive) {
                    guard let id = account.account?.userID else { return }
                    Task { _ = await model.act { try await DizzyCommunity.shared.deleteComment(discID: model.discID, userID: id) } }
                }
            }
    }
}

/// 撰写短评的表单：系统标准的「取消 / 发表」，正文 140 字以内。
private struct DiscCommentComposer: View {
    let model: DiscCommunityModel
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    private static let limit = 140

    private var count: Int { draft.unicodeScalars.count }
    private var canPost: Bool {
        !model.busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && count <= Self.limit
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextField("说说你对这张专辑的感受", text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(5...)
                    .focused($isFocused)
                Spacer(minLength: 0)
                HStack {
                    if let failure = model.failure {
                        Text(failure).font(.footnote).foregroundStyle(DizzyPalette.danger)
                    }
                    Spacer()
                    Text("\(count) / \(Self.limit)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(count > Self.limit ? DizzyPalette.danger : .secondary)
                }
            }
            .padding(20)
            .navigationTitle("撰写短评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.busy {
                        ProgressView()
                    } else {
                        Button("发表", role: .confirm) { post() }
                            .disabled(!canPost)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!draft.isEmpty)
        .onAppear { isFocused = true }
    }

    private func post() {
        guard let id = account.account?.userID else { account.isLoginPresented = true; return }
        let text = draft
        Task {
            if await model.act({ try await DizzyCommunity.shared.postComment(text, discID: model.discID, userID: id) }) {
                dismiss()
            }
        }
    }
}

// MARK: - 全部短评与 repo

/// 「查看全部」推入的页面：系统列表样式，顶部是 +dB 汇总，下面分「短评」和「repo」两栏。
struct DiscCommunityPage: View {
    let discID: String
    @Environment(AccountStore.self) private var account

    var body: some View {
        DiscCommunityList(discID: discID)
            .id("\(discID)-\(account.account?.userID ?? 0)-\(account.isSessionExpired)")
    }
}

private struct DiscCommunityList: View {
    @State private var model: DiscCommunityModel
    @State private var section: Section = .comments
    @State private var isComposing = false
    @State private var isConfirmingDelete = false
    @Environment(AccountStore.self) private var account

    enum Section: Hashable { case comments, reviews }

    init(discID: String) { _model = State(initialValue: DiscCommunityModel(discID: discID)) }

    var body: some View {
        List {
            SwiftUI.Section {
                DiscLikeSummary(model: model)
                    .padding(.vertical, 4)
            }
            .listRowBackground(DizzyPalette.surface)

            SwiftUI.Section {
                Picker("社区内容", selection: $section) {
                    Text("短评").tag(Section.comments)
                    Text("repo 长评").tag(Section.reviews)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let failure = model.failure {
                Text(failure).font(.footnote).foregroundStyle(DizzyPalette.danger)
                    .listRowBackground(DizzyPalette.surface)
            }

            switch section {
            case .comments: comments
            case .reviews: reviews
            }
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .navigationTitle("社区")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.context?.canComment == true && model.context?.myComment == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("撰写短评", systemImage: "square.and.pencil") { isComposing = true }
                }
            }
        }
        .refreshable {
            await model.refresh()
            await model.comments.reload()
            await model.reviews.reload()
        }
        .task { await model.refresh() }
        .discCommentComposer(model: model, isComposing: $isComposing, isConfirmingDelete: $isConfirmingDelete)
    }

    @ViewBuilder private var comments: some View {
        if let myComment = model.context?.myComment {
            SwiftUI.Section("我的短评") {
                Text(myComment).font(.subheadline).textSelection(.enabled)
                    .swipeActions {
                        Button("删除", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    }
                    .contextMenu {
                        Button("删除短评", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    }
            }
            .listRowBackground(DizzyPalette.surface)
        } else if !account.isLoggedIn || account.isSessionExpired {
            SwiftUI.Section {
                Button("登录后点赞和撰写短评") { account.isLoginPresented = true }
            }
            .listRowBackground(DizzyPalette.surface)
        }
        SwiftUI.Section {
            ForEach(model.comments.items) { comment in
                DiscCommentRow(comment: comment)
            }
            PagedListFooter(list: model.comments, emptyMessage: "还没有短评。")
        }
        .listRowBackground(DizzyPalette.surface)
    }

    private var reviews: some View {
        SwiftUI.Section {
            ForEach(model.reviews.items) { review in
                NavigationLink(value: AppRoute.review(id: review.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(review.title).font(.headline)
                        if !review.excerpt.isEmpty {
                            Text(review.excerpt).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Text([review.user?.name, review.date].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            PagedListFooter(list: model.reviews, emptyMessage: "还没有 repo。")
        }
        .listRowBackground(DizzyPalette.surface)
    }
}

/// 列表里的一条短评：头像和名字点进用户主页，正文可以选择复制。
private struct DiscCommentRow: View {
    let comment: DiscComment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                NavigationLink(value: AppRoute.user(id: comment.user.id)) {
                    HStack(spacing: 10) {
                        AvatarImage(url: comment.user.avatarURL, size: 32)
                        Text(comment.user.name).font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if let badge = comment.badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(comment.text).font(.subheadline).textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

/// 分页列表的最后一行：滚到这里自动加载下一页，失败时可以重试。
private struct PagedListFooter<Item: Identifiable & Sendable>: View {
    let list: PagedList<Item>
    let emptyMessage: String

    var body: some View {
        Group {
            if let failure = list.failure {
                VStack(alignment: .leading, spacing: 6) {
                    Text(failure).font(.footnote).foregroundStyle(DizzyPalette.danger)
                    Button("重试") { Task { await list.loadMore() } }
                }
            } else if list.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if list.isEmpty {
                Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary)
            } else if list.hasMore {
                ProgressView().frame(maxWidth: .infinity)
                    .task { await list.loadMore() }
            }
        }
        .task { if list.items.isEmpty && !list.isLoading { await list.loadMore() } }
    }
}

// MARK: - 其他页面共用

struct CommunityUserLink: View {
    let user: CommunityUser
    var body: some View {
        NavigationLink(value: AppRoute.user(id: user.id)) {
            HStack(spacing: 10) {
                AvatarImage(url: user.avatarURL, size: 36)
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
