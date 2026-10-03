import AppKit
import SwiftUI

/// 登录表单。密码只用于这一次登录，不保存；登录后的会话保存在本机钥匙串中。
struct LoginSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !isSubmitting && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("登录 DizzyLab").font(.title2.bold())
                Text("登录后可以收听已购专辑的完整版，查看已购买和关注动态。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            Form {
                Section {
                    TextField("昵称或邮箱", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(DizzyPalette.danger)
                        }
                        Text("密码只用于这一次登录，不会保存。登录后的会话保存在本机钥匙串中，只发送给 DizzyLab。")
                            .foregroundStyle(.secondary)
                        Link("在网页中注册或找回密码", destination: DizzyURL.login)
                    }
                    .font(.callout)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    if isSubmitting { ProgressView().controlSize(.small) } else { Text("登录") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task { focusedField = .username }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let username = username.trimmingCharacters(in: .whitespaces)
        let password = password
        Task {
            do {
                try await account.login(username: username, password: password)
                self.password = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

/// 工具栏右侧的账户按钮：头像与账户菜单。
struct AccountMenu: View {
    @Environment(AccountStore.self) private var account
    @Environment(MacAppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var isConfirmingLogout = false

    var body: some View {
        Menu {
            if let user = account.account {
                Text(user.nickname)
                if account.isSessionExpired {
                    Button("登录已失效，重新登录…") { account.isLoginPresented = true }
                }
                Button("我的主页") { model.navigation.open(.user(id: user.userID)) }
                Button("已购买") { model.navigation.selection = .tab(.purchased) }
                Divider()
                Button("设置…") { openSettings() }
                Button("退出登录") { isConfirmingLogout = true }
            } else {
                Button("登录…") { account.isLoginPresented = true }
                Divider()
                Button("设置…") { openSettings() }
            }
        } label: {
            if let user = account.account {
                Label {
                    Text(user.nickname)
                } icon: {
                    AvatarImage(url: user.avatarURL, size: 22)
                        .overlay(alignment: .bottomTrailing) {
                            if account.isSessionExpired {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DizzyPalette.danger)
                            }
                        }
                }
            } else {
                Label("账户", systemImage: "person.crop.circle")
            }
        }
        .help(account.account?.nickname ?? String(localized: "登录 DizzyLab"))
        .confirmationDialog("退出登录？", isPresented: $isConfirmingLogout) {
            Button("退出登录", role: .destructive) { Task { await account.logout() } }
        } message: {
            Text("会清除保存在本机的登录会话。")
        }
    }
}

/// 免责声明，与仓库里的 DISCLAIMER.md 内容一致。
struct DisclaimerText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NeoDizzy 是非官方的开源第三方客户端，与 DizzyLab 及其运营方不存在隶属、合作或授权关系。")
            Text("本项目出于学习与研究目的开发，通过 DizzyLab 网站本身提供的页面和接口获取信息。网站变化可能导致功能随时失效。")
            Text("账号凭据只保存在本机的钥匙串中，不会发送到 DizzyLab 以外的任何地方。")
            Text("请支持并尊重创作者：购买后下载的作品仅供个人使用，不要上传发布到任何公开的网络空间（包括免费作品）。")
            Text("本项目按 GPLv3 许可证提供，不附带任何担保；使用本项目产生的风险由使用者自行承担。")
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}

struct DisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("免责声明").font(.title2.bold())
            DisclaimerText()
            HStack {
                Spacer()
                Button("好") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
