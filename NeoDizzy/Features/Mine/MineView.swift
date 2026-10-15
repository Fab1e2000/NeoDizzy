import SwiftUI

/// 应用设置与本地存储管理，不展示平台账号。
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ModuleSettings.self) private var tabs
    @Environment(DownloadStore.self) private var downloads
    @Environment(ModuleRegistry.self) private var modules

    var body: some View {
        @Bindable var tabs = tabs
        @Bindable var downloads = downloads
        NavigationStack {
            List {
                Section("外观") {
                    NavigationLink { AppearanceSettingsView() } label: {
                        Label("外观与主题", systemImage: "paintpalette")
                    }
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
                    NavigationLink { TabSettingsView() } label: {
                        Label("模块管理", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                } header: {
                    Text("导航")
                }
                .listRowBackground(DizzyPalette.surface)

                Section("音乐库") {
                    NavigationLink { MusicFolderView() } label: {
                        Label("音乐文件夹", systemImage: "folder")
                    }
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
                    NavigationLink { LyricsSettingsView() } label: {
                        Label("歌词", systemImage: "text.quote")
                    }
                }
                .listRowBackground(DizzyPalette.surface)

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.versionText)
                    LabeledContent("开源许可", value: "GPLv3")
                    NavigationLink("免责声明") {
                        DisclaimerView()
                    }
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

}

private extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
