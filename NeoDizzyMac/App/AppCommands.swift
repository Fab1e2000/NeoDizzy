import SwiftUI

/// 菜单栏命令，分组参考 Music：文件、编辑、显示、控制、账户、窗口和帮助。
struct AppCommands: Commands {
    let model: MacAppModel
    @Environment(\.openWindow) private var openWindow

    private var player: PlayerStore { model.player }
    private var account: AccountStore { model.account }
    private var library: OfflineLibraryStore { model.services.offlineLibrary }

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("添加音乐文件夹…") {
                Task {
                    guard let url = await FolderPanel.chooseFolder(message: String(localized: "选择要加入本地库的音乐文件夹。只读取音乐文件，不会修改它们。"),
                                                                   prompt: String(localized: "添加")) else { return }
                    do { try await library.addScanFolder(url) } catch { debugLog("添加扫描目录失败：\(error)") }
                }
            }
            .keyboardShortcut("o")
            Button("重新扫描本地库") { Task { await library.scan() } }
                .disabled(library.isScanning)
        }

        CommandGroup(after: .textEditing) {
            Button("搜索") { model.showSearch() }
                .keyboardShortcut("f")
        }

        CommandGroup(before: .sidebar) {
            Button("刷新") {
                guard let refresh = model.refresh else { return }
                Task { await refresh.action() }
            }
            .keyboardShortcut("r")
            .disabled(model.refresh == nil)
            Divider()
            Toggle("歌词", isOn: panelBinding(.lyrics))
                .keyboardShortcut("l", modifiers: [.command, .option])
            Toggle("待播清单", isOn: panelBinding(.queue))
                .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("控制") {
            Button(player.isPlaying ? "暂停" : "播放") { player.togglePlayback() }
                .disabled(player.currentTrack == nil)
            Divider()
            Button("下一首") { player.next() }
                .keyboardShortcut(.rightArrow)
                .disabled(player.currentTrack == nil || !player.canPlayNext)
            Button("上一首") { player.previous() }
                .keyboardShortcut(.leftArrow)
                .disabled(player.currentTrack == nil || !player.canPlayPrevious)
            Divider()
            Button("增大音量") { model.changeVolume(by: 0.1) }
                .keyboardShortcut(.upArrow)
            Button("减小音量") { model.changeVolume(by: -0.1) }
                .keyboardShortcut(.downArrow)
            Divider()
            Toggle("随机播放", isOn: Binding(get: { player.isShuffled }, set: { if $0 != player.isShuffled { player.toggleShuffle() } }))
                .disabled(player.isDiscovery || player.currentTrack == nil)
            Picker("重复", selection: Binding(get: { player.repeatMode }, set: { mode in
                for _ in RepeatMode.allCases where player.repeatMode != mode { player.cycleRepeatMode() }
            })) {
                Text("关闭").tag(RepeatMode.off)
                Text("全部").tag(RepeatMode.all)
                Text("单曲").tag(RepeatMode.one)
            }
            .disabled(player.isDiscovery || player.currentTrack == nil)
            Divider()
            Button("前往当前歌曲") {
                if let route = model.currentAlbumRoute { model.open(route) }
            }
            .keyboardShortcut("l")
            .disabled(model.currentAlbumRoute == nil)
        }

        CommandMenu("账户") {
            if let user = account.account {
                Text(account.isSessionExpired ? "\(user.nickname)（登录已失效）" : user.nickname)
                if account.isSessionExpired {
                    Button("重新登录…") { presentLogin() }
                }
                Button("我的主页") { model.open(.user(id: user.userID)) }
                Button("已购买") {
                    model.openMainWindow()
                    model.navigation.selection = .tab(.purchased)
                }
                Divider()
                Button("退出登录") { Task { await account.logout() } }
            } else {
                Button("登录…") { presentLogin() }
            }
        }

        CommandGroup(before: .windowList) {
            Button("NeoDizzy") { openWindow(id: SceneID.main) }
                .keyboardShortcut("1")
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("免责声明") {
                openWindow(id: SceneID.main)
                model.isDisclaimerPresented = true
            }
            Divider()
            Link("访问 DizzyLab 官网", destination: DizzyURL.site)
            Link("反馈问题", destination: URL(string: "https://github.com/Fab1e2000/NeoDizzy/issues")!)
        }
    }

    private func panelBinding(_ panel: PlayerPanel) -> Binding<Bool> {
        Binding(get: { model.playerPanel == panel }, set: { model.playerPanel = $0 ? panel : nil })
    }

    private func presentLogin() {
        openWindow(id: SceneID.main)
        account.isLoginPresented = true
    }
}
