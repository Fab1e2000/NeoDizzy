import SwiftUI

/// 「我的」：账号卡片和关于。从各页页头的头像按钮弹出。
struct MineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @State private var isConfirmingLogout = false
    @State private var isLoggingOut = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
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
                Link("在网页中查看个人主页", destination: DizzyURL.page("/u/\(user.userID)"))
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
