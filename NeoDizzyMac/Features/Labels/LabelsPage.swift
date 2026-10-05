import SwiftUI

/// 全部社团。
struct LabelsPage: View {
    @Environment(MacAppModel.self) private var model

    var body: some View {
        PageScroll(title: String(localized: "社团")) {
            PagedSection(list: model.labels, webURL: DizzyURL.page("/label/")) { labels in
                LazyVGrid(columns: PageMetrics.rowColumns, alignment: .leading, spacing: 12) {
                    ForEach(labels) { label in
                        LabelRow(name: label.name, coverURL: label.coverURL, description: label.description,
                                 recentDiscs: label.recentDiscs)
                    }
                }
            }
        }
        .pageRefresh { await model.labels.reload() }
    }
}

/// 社团页：头像、关注、简介、pack 与全部作品。
struct LabelDetailPage: View {
    let name: String
    @State private var page: Loadable<LabelPage>

    init(name: String) {
        self.name = name
        _page = State(initialValue: Loadable { try await DizzyPages.shared.label(name: name) })
    }

    var body: some View {
        LoadablePage(state: page, webURL: DizzyURL.label(name)) { label in
            PageScroll {
                header(label)
                if !label.description.isEmpty {
                    ExpandableText(text: label.description)
                }
                if !label.packs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("pack")
                        LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                            ForEach(label.packs) { PackCard(pack: $0) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(String(localized: "作品 \(label.discs.count)"))
                    DiscGrid(discs: label.discs, showsLabel: false)
                }
                if !label.history.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(label.history, id: \.self) { Text($0) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(name)
        .pageRefresh { await page.load() }
    }

    private func header(_ label: LabelPage) -> some View {
        HStack(alignment: .center, spacing: 22) {
            AvatarImage(url: label.coverURL, size: 140)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(label.name).font(.pageTitle).lineLimit(2).textSelection(.enabled)
                if let followers = label.followerCount {
                    Text("\(followers) 人关注").foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    FollowLabelButton(name: name, onChanged: { await page.load() })
                    Link(destination: DizzyURL.label(name)) { Label("在浏览器中打开", systemImage: "safari") }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 关注 / 取消关注社团。与 iOS 相同：先读取当前账号的关注状态，修改后通知关注页刷新。
struct FollowLabelButton: View {
    let name: String
    var onChanged: (() async -> Void)?
    @Environment(AccountStore.self) private var account
    @State private var state: CommunityPageParser.Follow?
    @State private var busy = false
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard let id = account.account?.userID, !account.isSessionExpired else { account.isLoginPresented = true; return }
                guard loaded, !busy else { return }
                busy = true
                let desired = !(state?.isFollowing ?? false)
                Task {
                    defer { busy = false }
                    do {
                        _ = try await DizzyCommunity.shared.setFollowing(desired, name: name, userID: id)
                        await refresh()
                        await onChanged?()
                        NotificationCenter.default.post(name: .dizzyFollowingDidChange, object: nil)
                    } catch { failure = error.localizedDescription; await reloadState() }
                }
            } label: {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Label(state?.isFollowing == true ? "已关注" : "关注", systemImage: state?.isFollowing == true ? "checkmark" : "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(state?.isFollowing == true ? .secondary : .dizzyAccent)
            .disabled(busy || (account.isLoggedIn && !loaded))
            .help(state?.isFollowing == true ? "取消关注" : "关注社团")
            if let failure {
                Text(failure).font(.callout).foregroundStyle(DizzyPalette.danger).lineLimit(2)
                Button("重试") { Task { await refresh() } }.buttonStyle(.link)
            }
        }
        .task(id: "\(account.account?.userID ?? 0)-\(account.isSessionExpired)") { state = nil; loaded = false; await refresh() }
    }

    private func refresh() async {
        failure = nil
        await reloadState()
    }

    private func reloadState() async {
        guard account.isLoggedIn, !account.isSessionExpired else { loaded = true; return }
        do {
            let current = try await DizzyCommunity.shared.followState(name)
            try Task.checkCancellation()
            guard current?.userID == account.account?.userID else { throw DizzyError.sessionExpired }
            state = current; loaded = true
        } catch is CancellationError {} catch { failure = error.localizedDescription }
    }
}
