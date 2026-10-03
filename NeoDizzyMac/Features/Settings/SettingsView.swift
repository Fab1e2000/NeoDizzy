import AppKit
import SwiftUI

/// 设置窗口（⌘,）：通用、播放、资料库、账户与关于。
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") { GeneralSettings() }
            Tab("播放", systemImage: "play.circle") { PlaybackSettings() }
            Tab("资料库", systemImage: "square.stack") { LibrarySettings() }
            Tab("账户", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("关于", systemImage: "info.circle") { AboutSettings() }
        }
        .scenePadding()
        .frame(width: 560)
    }
}

/// 启动页面与侧边栏项目（显示、隐藏与顺序），对应 iOS 的「标签栏」设置。
private struct GeneralSettings: View {
    @Environment(TabSettings.self) private var tabs

    var body: some View {
        @Bindable var tabs = tabs
        Form {
            Picker("启动时显示", selection: $tabs.startupTab) {
                ForEach(MainTab.primary) { tab in
                    Text(tab.title + (tabs.isVisible(tab) ? "" : String(localized: "（已隐藏）"))).tag(tab)
                }
            }
            Section {
                List {
                    ForEach(tabs.order) { tab in
                        Toggle(isOn: Binding(get: { tabs.isVisible(tab) }, set: { tabs.setVisible($0, for: tab) })) {
                            Label(tab.title, systemImage: SidebarItem.tab(tab).systemImage)
                        }
                        .disabled(!tabs.canHide(tab))
                    }
                    .onMove { offsets, destination in
                        var order = tabs.order
                        order.move(fromOffsets: offsets, toOffset: destination)
                        tabs.reorder(order)
                    }
                }
                .frame(height: 190)
                Button("恢复默认") { tabs.reset() }
            } header: {
                Text("侧边栏")
            } footer: {
                Text("拖动调整顺序，至少保留一个页面。搜索、最近浏览和下载始终显示。")
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}

/// 歌词高亮位置。
private struct PlaybackSettings: View {
    @AppStorage("lyrics.focusPosition") private var focusPosition = 0.5

    var body: some View {
        Form {
            Section {
                LabeledContent("高亮行位置") {
                    HStack {
                        Slider(value: $focusPosition, in: 0.05...0.8, step: 0.01)
                        Text("距顶部 \(Int(focusPosition * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                }
                Button("恢复居中") { focusPosition = 0.5 }
            } header: {
                Text("歌词")
            } footer: {
                Text("只读取本地歌词：手动导入的 LRC / TXT、同目录同名 LRC 或音频内嵌歌词，不联网搜索。")
            }
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}

/// 下载目录与其他扫描目录。
private struct LibrarySettings: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var isChanging = false
    @State private var issue: String?

    var body: some View {
        Form {
            Section("下载目录") {
                DownloadFolderSection()
            }
            Section {
                if library.scanFolders.isEmpty {
                    Text("还没有添加其他扫描目录。").foregroundStyle(.secondary)
                }
                ForEach(library.scanFolders) { folder in
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        if let issue = folder.issue {
                            Text(issue).font(.callout).foregroundStyle(Color.dizzyGold).lineLimit(2)
                        }
                        Spacer()
                        Button("重新授权…") { Task { await choose(replacing: folder.id) } }
                        Button("移除", role: .destructive) {
                            isChanging = true
                            Task { await library.removeScanFolder(folder.id); isChanging = false }
                        }
                    }
                }
                HStack {
                    Button("添加文件夹…") { Task { await choose(replacing: nil) } }
                    Spacer()
                    if isChanging || library.isScanning { ProgressView().controlSize(.small) }
                    Button("重新扫描") { Task { await library.scan() } }
                }
                if let issue = issue ?? library.issue {
                    Text(issue).font(.callout).foregroundStyle(Color.dizzyGold)
                }
            } header: {
                Text("其他扫描目录")
            } footer: {
                Text("扫描只读取音乐文件。每个直接包含音频的文件夹是一张专辑；移除目录不会删除文件，下载目录始终包含在本地库中。")
            }
            .disabled(isChanging || library.isScanning)
        }
        .formStyle(.grouped)
        .frame(height: 440)
    }

    private func choose(replacing id: UUID?) async {
        guard let url = await FolderPanel.chooseFolder(message: String(localized: "选择要加入本地库的音乐文件夹。只读取音乐文件，不会修改它们。"),
                                                       prompt: String(localized: id == nil ? "添加" : "授权")) else { return }
        isChanging = true
        issue = nil
        defer { isChanging = false }
        do { try await library.addScanFolder(url, replacing: id) } catch { issue = error.localizedDescription }
    }
}

private struct AccountSettings: View {
    @Environment(AccountStore.self) private var account
    @Environment(MacAppModel.self) private var model
    @State private var isConfirmingLogout = false
    @State private var showsLogin = false

    var body: some View {
        Form {
            if let user = account.account {
                Section {
                    HStack(spacing: 14) {
                        AvatarImage(url: user.avatarURL, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.nickname).font(.headline)
                            if account.isSessionExpired {
                                Label("登录已失效", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DizzyPalette.danger)
                            } else {
                                Text("已登录，已购专辑可以收听完整版。").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if account.isSessionExpired {
                        Button("重新登录…") { showsLogin = true }
                    }
                    Button("打开个人主页") { model.open(.user(id: user.userID)) }
                    Button("退出登录", role: .destructive) { isConfirmingLogout = true }
                }
            } else {
                Section {
                    Text("未登录").font(.headline)
                    Text("登录后可以收听已购专辑的完整版，查看已购买和关注动态。").foregroundStyle(.secondary)
                    Button("登录 DizzyLab…") { showsLogin = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 260)
        .sheet(isPresented: $showsLogin) { LoginSheet() }
        .confirmationDialog("退出登录？", isPresented: $isConfirmingLogout) {
            Button("退出登录", role: .destructive) { Task { await account.logout() } }
        } message: {
            Text("会清除保存在本机的登录会话。")
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NeoDizzy").font(.title2.bold())
                    Text("版本 \(Bundle.main.versionText)").foregroundStyle(.secondary)
                    Text("第三方 DizzyLab 音乐客户端 · GPLv3").foregroundStyle(.secondary)
                }
            }
            ScrollView {
                DisclaimerText()
                    .foregroundStyle(.secondary)
            }
            .frame(height: 170)
            HStack(spacing: 16) {
                Link("访问 DizzyLab 官网", destination: DizzyURL.site)
                Link("源代码与反馈", destination: URL(string: "https://github.com/Fab1e2000/NeoDizzy")!)
            }
        }
        .padding(8)
        .frame(height: 320, alignment: .top)
    }
}
