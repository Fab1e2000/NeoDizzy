import SwiftUI

/// 原生登录表单。密码只用于这一次登录，不保存；登录后的会话存在本机钥匙串里。
struct LoginView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case username, password
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("昵称或邮箱", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)
            } footer: {
                Text("密码只用于这一次登录，不会保存。登录后的会话保存在本机钥匙串中，只发送给 DizzyLab。")
            }
            .listRowBackground(DizzyPalette.surface)

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DizzyPalette.danger)
                }
                .listRowBackground(DizzyPalette.surface)
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("登录").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
            .listRowBackground(DizzyPalette.surface)

            Section {
                Link("在网页中注册或找回密码", destination: DizzyURL.login)
            }
            .listRowBackground(DizzyPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .navigationTitle("登录 DizzyLab")
        .navigationBarTitleDisplayMode(.inline)
        .task { focusedField = .username }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        focusedField = nil
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

/// 需要登录的页面在未登录或登录失效时显示的提示。
struct LoginPrompt: View {
    @Environment(AccountStore.self) private var account
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(DizzyPalette.accent)
            Text(account.isSessionExpired ? "登录已失效" : "登录 DizzyLab")
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
                .multilineTextAlignment(.center)
            Button(account.isSessionExpired ? "重新登录" : "登录") {
                account.isLoginPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 20))
    }
}
