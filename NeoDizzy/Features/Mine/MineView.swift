import SwiftUI

/// 「我的」：账号卡片和关于。从各页页头的头像按钮弹出。
struct MineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabSettings.self) private var tabs
    @Environment(AccountStore.self) private var account
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @State private var isConfirmingLogout = false
    @State private var isLoggingOut = false

    var body: some View {
        @Bindable var tabs = tabs
        NavigationStack {
            List {
                accountSection
                    .listRowBackground(DizzyPalette.surface)

                Section {
                    NavigationLink { BrowsingHistoryView() } label: {
                        Label("浏览记录", systemImage: "clock.arrow.circlepath")
                    }
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    Picker("启动页面", selection: $tabs.startupTab) {
                        ForEach(MainTab.primary) { tab in
                            Text(tab.title + (tabs.isVisible(tab) ? "" : "（已隐藏）")).tag(tab)
                        }
                    }
                    NavigationLink("扫描目录") { LibraryFoldersView() }
                    NavigationLink("标签栏") { TabSettingsView() }
                    NavigationLink("歌词") { LyricsSettingsView() }
                    Picker("标题栏", selection: $pinsTitleBar) {
                        Text("固定").tag(true)
                        Text("滚动").tag(false)
                    }
                } header: {
                    Text("设置")
                } footer: {
                    Text(pinsTitleBar ? "主页面标题固定在顶部。" : "主页面标题随内容滚动，下拉时保持原位。")
                }
                .listRowBackground(DizzyPalette.surface)

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.versionText)
                    LabeledContent("开源许可", value: "GPLv3")
                    NavigationLink("免责声明") {
                        DisclaimerView()
                    }
                    Link("访问 DizzyLab 官网", destination: URL(string: "https://www.dizzylab.net")!)
                }
                .listRowBackground(DizzyPalette.surface)
            }
            .scrollContentBackground(.hidden)
            .dizzyPageBackground()
            .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var accountSection: some View {
        if let user = account.account {
            Section {
                HStack(spacing: 14) {
                    ArtworkImage(url: user.avatarURL, cornerRadius: 26)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.nickname)
                            .font(.headline)
                        if account.isSessionExpired {
                            Label("登录已失效", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(DizzyPalette.danger)
                        } else {
                            Text("已登录，已购专辑可以收听完整版。")
                                .font(.footnote)
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                    }
                }
                .padding(.vertical, 4)
                if account.isSessionExpired {
                    NavigationLink("重新登录") { LoginView() }
                }
                NavigationLink("个人主页", value: AppRoute.user(id: user.userID))
                Button("退出登录", role: .destructive) {
                    isConfirmingLogout = true
                }
                .disabled(isLoggingOut)
                .confirmationDialog("退出登录？", isPresented: $isConfirmingLogout, titleVisibility: .visible) {
                    Button("退出登录", role: .destructive) {
                        isLoggingOut = true
                        Task {
                            await account.logout()
                            isLoggingOut = false
                        }
                    }
                } message: {
                    Text("会清除保存在本机的登录会话。")
                }
            }
        } else {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(DizzyPalette.mutedText)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未登录")
                            .font(.headline)
                        Text("登录后可以收听已购专辑的完整版，查看已购专辑和关注动态。")
                            .font(.footnote)
                            .foregroundStyle(DizzyPalette.mutedText)
                    }
                }
                .padding(.vertical, 4)
                NavigationLink("登录 DizzyLab 账号") { LoginView() }
            }
        }
    }
}

private extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
