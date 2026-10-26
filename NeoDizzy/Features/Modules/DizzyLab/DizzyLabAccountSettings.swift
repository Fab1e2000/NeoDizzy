import SwiftUI

struct DizzyLabAccountView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List { DizzyLabAccountSettings() }
                .scrollContentBackground(.hidden)
                .dizzyPageBackground()
                .navigationTitle("DizzyLab 账号")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

struct DizzyLabAccountSettings: View {
    @Environment(AccountStore.self) private var account
    @State private var isConfirmingLogout = false
    @State private var isLoggingOut = false

    var body: some View {
        accountSection.listRowBackground(DizzyPalette.surface)
        if let error = account.sessionError {
            Section {
                Text(error).foregroundStyle(.red)
                Button("重试清除凭据") { Task { await account.logout() } }
            }
        }
        Section {
            Link("访问 DizzyLab 官网", destination: DizzyURL.site)
        }
        .listRowBackground(DizzyPalette.surface)
    }

    @ViewBuilder
    private var accountSection: some View {
        if let user = account.account {
            Section {
                HStack(spacing: 14) {
                    DizzyLabAvatarImage(url: user.avatarURL, size: 52)
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
                    NavigationLink("重新登录", value: AppRoute.page { LoginView() })
                }
                NavigationLink("个人主页", value: AppRoute.user(id: user.userID))
                Button(role: .destructive) {
                    isConfirmingLogout = true
                } label: {
                    HStack {
                        Label(isLoggingOut ? "正在退出登录…" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if isLoggingOut { ProgressView().accessibilityHidden(true) }
                    }
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
                    Text("未登录")
                        .font(.headline)
                }
                .padding(.vertical, 4)
                NavigationLink("登录 DizzyLab 账号", value: AppRoute.page { LoginView() })
            }
        }
    }
}
