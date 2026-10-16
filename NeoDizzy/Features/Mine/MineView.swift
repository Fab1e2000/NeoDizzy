import SwiftUI

/// 应用设置、各平台账号入口与本地存储管理。
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ModuleSettings.self) private var tabs
    @Environment(DownloadStore.self) private var downloads
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AppSettingsPresentation.self) private var presentation
    @AppStorage(ImmersiveMode.storageKey) private var isImmersive = false

    var body: some View {
        @Bindable var tabs = tabs
        @Bindable var downloads = downloads
        NavigationStack {
            List {
                Section("账号") {
                    ForEach(modules.descriptors) { module in
                        if let entry = modules.accountEntry(for: module.id) {
                            accountRow(module, entry: entry)
                        }
                    }
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    NavigationLink(value: AppRoute.page { AppearanceSettingsView() }) {
                        Label("外观与主题", systemImage: "paintpalette")
                    }
                    Toggle(isOn: $isImmersive) {
                        Label("沉浸模式", systemImage: "rectangle.dashed")
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("隐藏屏幕顶部的时间、电量和信号。")
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    Picker(selection: $tabs.startupModule) {
                        ForEach(modules.descriptors) { tab in
                            Text(tab.title + (tabs.isVisible(tab.id) ? "" : "（已隐藏）")).tag(tab.id)
                        }
                    } label: {
                        Label("启动页面", systemImage: "house")
                    }
                    NavigationLink(value: AppRoute.page { TabSettingsView() }) {
                        Label("模块管理", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                } header: {
                    Text("导航")
                }
                .listRowBackground(DizzyPalette.surface)

                Section("音乐库") {
                    LibraryExportButton()
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    Picker("并行下载数量", selection: $downloads.concurrentDownloadCount) {
                        ForEach(Array(DownloadStore.concurrentDownloadRange), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                } header: {
                    Text("下载")
                } footer: {
                    Text("下载与音频处理同时进行。调低数量后，已开始的下载会继续，后续按新数量调度。")
                }
                .listRowBackground(DizzyPalette.surface)

                Section("播放") {
                    NavigationLink(value: AppRoute.page { LyricsSettingsView() }) {
                        Label("歌词", systemImage: "text.quote")
                    }
                }
                .listRowBackground(DizzyPalette.surface)

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.versionText)
                    LabeledContent("开源许可", value: "GPLv3")
                    NavigationLink("免责声明", value: AppRoute.page { DisclaimerView() })
                }
                .listRowBackground(DizzyPalette.surface)
            }
            .scrollContentBackground(.hidden)
            .dizzyPageBackground()
            .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            .safeAreaPadding(.top, 5)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }


    /// 一个平台的账号：已登录显示头像，点一下收起设置，再打开该平台的账号页或登录页。
    private func accountRow(_ module: ModuleDescriptor, entry: ModuleAccountEntry) -> some View {
        Button {
            presentation.pendingAccount = module.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let url = entry.avatarURL {
                        AvatarImage(url: url, size: 32)
                    } else {
                        Image(systemName: module.systemImage)
                            .font(.body)
                            .foregroundStyle(DizzyPalette.accent)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(.circle)
                .accessibilityHidden(true)
                Text(entry.title).foregroundStyle(DizzyPalette.text)
                Spacer()
                Text(entry.isSignedIn ? "已登录" : "登录").foregroundStyle(DizzyPalette.mutedText)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// 沉浸模式的开关存在 UserDefaults 里，根视图和各个弹层一起读取。
enum ImmersiveMode {
    static let storageKey = "appearance.immersive"
}
