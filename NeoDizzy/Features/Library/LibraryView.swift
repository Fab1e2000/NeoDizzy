import SwiftUI

struct LibraryView: View {
    var body: some View {
        MainTabPage(tab: .library) {
            PlaceholderCard(
                systemImage: "music.note.list",
                title: "已购与已下载",
                message: "登录后显示你买过的专辑；下载到文件夹里的专辑可以离线播放。"
            )
        }
    }
}
