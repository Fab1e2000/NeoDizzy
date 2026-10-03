import NukeUI
import SwiftUI

/// 专辑页底部的社区：+dB、短评与 repo 长评。与 iOS 相同，点开后才请求，本地专辑不会因此发起社区请求。
struct CommunitySection: View {
    let discID: String
    @Environment(AccountStore.self) private var account
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "社区")) {
                Button(isExpanded ? "收起" : "显示 +dB、短评与 repo") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .buttonStyle(.link)
            }
            if isExpanded {
                CommunityContent(discID: discID)
                    .id("\(discID)-\(account.account?.userID ?? 0)-\(account.isSessionExpired)")
            }
        }
    }
}

private struct CommunityContent: View {
    @Environment(AccountStore.self) private var account
    @State private var model: DiscCommunityModel
    @State private var draft = ""
    @State private var deleting = false
    @State private var showsReviews = false

    init(discID: String) { _model = State(initialValue: DiscCommunityModel(discID: discID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button {
                    guard let id = account.account?.userID, !account.isSessionExpired else { account.isLoginPresented = true; return }
                    Task { _ = await model.act { model.likes = try await DizzyCommunity.shared.toggleLike(model.discID, userID: id) } }
                } label: {
                    Label(model.likes.map { "+\($0.likes * 2) dB" } ?? "+2 dB",
                          systemImage: model.likes?.ilikethis == true ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered)
                .tint(model.likes?.ilikethis == true ? .dizzyGold : nil)
                .help(model.likes?.ilikethis == true ? "取消 +dB" : "+2 dB")
                .disabled(model.busy || !model.loaded)
                Picker("社区内容", selection: $showsReviews) {
                    Text("短评").tag(false)
                    Text("repo 长评").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button {
                    Task { await model.refresh(); await model.comments.reload(); await model.reviews.reload() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(model.busy)
                    .help("刷新社区")
            }
            if let failure = model.failure { Text(failure).foregroundStyle(DizzyPalette.danger) }
            if !model.loaded && model.failure == nil { ProgressView().controlSize(.small) }
            composer
            if showsReviews {
                CommunityList(list: model.reviews, emptyMessage: "还没有 repo。") { reviews in
                    ForEach(reviews) { ReviewRow(review: $0) }
                }
            } else {
                CommunityList(list: model.comments, emptyMessage: "还没有短评。") { comments in
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            UserLink(user: comment.user)
                            Text(comment.text).textSelection(.enabled)
                            if let badge = comment.badge { Text(badge).font(.caption).foregroundStyle(.secondary) }
                            Divider().padding(.top, 6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .task { await model.refresh() }
        .confirmationDialog("删除自己的短评？", isPresented: $deleting) {
            Button("删除短评", role: .destructive) {
                guard let id = account.account?.userID else { return }
                Task { _ = await model.act { try await DizzyCommunity.shared.deleteComment(discID: model.discID, userID: id) } }
            }
        }
    }

    @ViewBuilder private var composer: some View {
        if model.context?.myComment != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的短评").font(.headline)
                if let text = model.context?.myComment, !text.isEmpty { Text(text).textSelection(.enabled) }
                Button("删除我的短评", role: .destructive) { deleting = true }
                    .disabled(model.busy)
            }
        } else if model.context?.canComment == true {
            VStack(alignment: .trailing, spacing: 6) {
                TextField("写一条短评（140 字以内）", text: $draft, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("\(draft.unicodeScalars.count) / 140")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(draft.unicodeScalars.count > 140 ? DizzyPalette.danger : .secondary)
                    Spacer()
                    Button("发表") {
                        guard let id = account.account?.userID else { account.isLoginPresented = true; return }
                        let text = draft
                        Task { if await model.act({ try await DizzyCommunity.shared.postComment(text, discID: model.discID, userID: id) }) { draft = "" } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 140)
                }
            }
        } else if !account.isLoggedIn || account.isSessionExpired || (model.loaded && model.context?.userID == nil) {
            Button("登录后 +dB 和发表短评") { account.isLoginPresented = true }
                .buttonStyle(.link)
        }
    }
}

/// repo 长评摘要，点击进入阅读页。
struct ReviewRow: View {
    let review: ReviewSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let user = review.user { UserLink(user: user) }
            NavigationLink(value: AppRoute.review(id: review.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.title).font(.headline)
                    if !review.excerpt.isEmpty { Text(review.excerpt).foregroundStyle(.secondary).lineLimit(3) }
                    if let date = review.date { Text(date).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Divider().padding(.top, 4)
        }
    }
}

/// 社区里的分页列表：显式点击「加载更多」，不预先加载所有页。
private struct CommunityList<Item: Identifiable & Sendable, Content: View>: View {
    let list: PagedList<Item>
    let emptyMessage: String
    @ViewBuilder var content: ([Item]) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content(list.items)
            if let failure = list.failure {
                Text(failure).foregroundStyle(DizzyPalette.danger)
                Button("重试") { Task { await list.loadMore() } }
            } else if list.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if list.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            } else if list.hasMore {
                Button("加载更多") { Task { await list.loadMore() } }
                    .frame(maxWidth: .infinity)
            }
        }
        .task { if list.items.isEmpty { await list.loadMore() } }
    }
}

/// 用户主页：头像、简介，以及已购、repo、关注和 +2 dB 四类内容。
struct UserPage: View {
    @State private var model: CommunityProfileModel

    init(userID: Int) { _model = State(initialValue: CommunityProfileModel(userID: userID)) }

    var body: some View {
        PageScroll {
            if let profile = model.profile {
                HStack(spacing: 20) {
                    AvatarImage(url: profile.user.avatarURL, size: 110)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.user.name).font(.pageTitle)
                        if !profile.joined.isEmpty { Text(profile.joined).foregroundStyle(.secondary) }
                        if !profile.bio.isEmpty { Text(profile.bio).textSelection(.enabled).frame(maxWidth: 600, alignment: .leading) }
                    }
                }
            }
            Picker("用户内容", selection: $model.section) {
                ForEach(ProfileSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            switch model.section {
            case .following:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], alignment: .leading, spacing: 12) {
                    ForEach(model.labels) { LabelRow(name: $0.name, coverURL: $0.coverURL, description: $0.description) }
                }
            case .review:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.reviews) { ReviewRow(review: $0) }
                }
                .frame(maxWidth: 760, alignment: .leading)
            case .music, .likes:
                DiscGrid(discs: model.discs)
            }
            if let failure = model.failure {
                FailureView(message: failure, webURL: DizzyURL.page("/u/\(model.userID)/\(model.section.rawValue)/")) { await model.next() }
            } else if model.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if model.profile?.hasMore == true {
                Button("加载更多") { Task { await model.next() } }.frame(maxWidth: .infinity)
            } else if model.profile != nil && model.discs.isEmpty && model.labels.isEmpty && model.reviews.isEmpty {
                ContentUnavailableView("这里还没有内容", systemImage: "tray").padding(.vertical, 30)
            }
        }
        .navigationTitle(model.profile?.user.name ?? String(localized: "用户主页"))
        .task(id: model.section) { await model.reset() }
        .pageRefresh { await model.reset() }
    }
}

/// repo 长评阅读页。回复仍在网页中查看。
struct ReviewPage: View {
    let id: Int
    @State private var state: Loadable<ReviewDetail>

    init(id: Int) {
        self.id = id
        _state = State(initialValue: Loadable {
            let html = try await DizzyHTTPClient.shared.html(path: "/review/\(id)/")
            return try CommunityPageParser.review(html)
        })
    }

    var body: some View {
        LoadablePage(state: state, webURL: DizzyURL.page("/review/\(id)/")) { review in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(review.title).font(.pageTitle).textSelection(.enabled)
                    if let user = review.user { UserLink(user: user) }
                    Text(review.text)
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                    ForEach(review.images, id: \.self) { url in
                        LazyImage(url: url) { state in
                            if let image = state.image { image.resizable().scaledToFit() }
                            else if state.error != nil { Label("图片加载失败", systemImage: "photo").foregroundStyle(.secondary) }
                            else { ProgressView().frame(maxWidth: .infinity).padding(30) }
                        }
                        .frame(maxWidth: 720)
                    }
                    Link("在网页查看回复", destination: DizzyURL.page("/review/\(id)/"))
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, PageMetrics.margin)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("repo 长评")
        .pageRefresh { await state.load() }
    }
}
