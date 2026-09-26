import SwiftUI

/// 「我的」：账号卡片和关于。从各页页头的头像按钮弹出。
struct MineView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(DizzyPalette.mutedText)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("未登录")
                                .font(.headline)
                            Text("登录后可以听完整版、购买和下载已购专辑。")
                                .font(.footnote)
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("登录 DizzyLab 账号") {}
                        .disabled(true)
                } footer: {
                    Text("账号功能正在开发中。")
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
}

private extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
