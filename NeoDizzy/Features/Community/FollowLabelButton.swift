import SwiftUI

extension Notification.Name {
    static let dizzyFollowingDidChange = Notification.Name("dizzyFollowingDidChange")
}
struct FollowLabelButton: View {
    let name: String
    var onChanged: (() async -> Void)?
    @Environment(AccountStore.self) private var account
    @State private var state: CommunityPageParser.Follow?
    @State private var busy = false
    @State private var failure: String?
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Label(busy ? "正在更新…" : state?.isFollowing == true ? "已关注 · 取消关注" : "关注社团", systemImage: state?.isFollowing == true ? "checkmark" : "plus")
            }.buttonStyle(.bordered).disabled(busy || (account.isLoggedIn && !loaded))
            if let failure {
                Text(failure).font(.caption).foregroundStyle(DizzyPalette.danger)
                HStack {
                    Button("重新读取状态") { Task { await refresh() } }
                    Button("重新登录") { account.isLoginPresented = true }
                }.font(.caption)
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
