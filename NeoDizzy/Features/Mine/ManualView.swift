import SwiftUI

/// 使用说明：共用规则与可选平台功能集中放在这里。
struct ManualTopic: Identifiable {
    let title: String
    let systemImage: String
    let items: [String]
    var id: String { title }

    static let all: [ManualTopic] = [
        .init(title: "平台模块", systemImage: "square.stack.3d.up", items: [
            "以下涉及具体平台的说明，仅适用于已安装并启用的对应模块；部分功能还需要登录和相应账号权限。",
            "本地资料库、播放队列和下载管理由应用共用，各平台独立登录。",
            "在「模块设置」中隐藏入口只改变导航显示；关闭平台服务会停止该平台的在线播放、同步与未完成下载。",
            "关闭平台服务后，账号凭据、资料库记录和已下载文件仍会保留。",
        ]),
        .init(title: "歌曲图标", systemImage: "arrow.down.circle", items: [
            "实心箭头：已下载，永久保存在手机里。",
            "空心箭头：已缓存，没网也能播放，但空间不足时可能被清理。",
            "没有图标：未下载，播放时需要联网。",
            "已缓存的网易云或 QQ 音乐歌曲，菜单里的「下载」会变成「转为下载」：直接用缓存文件，不再联网。歌曲列表、播放页和「喜欢」里都有这个入口。",
            "DizzyLab 只能整张专辑下载，缓存的歌没有「转为下载」。",
        ]),
        .init(title: "听歌缓存", systemImage: "internaldrive", items: [
            "在线播放的完整音频会自动保存，最多 2 GB。空间不足时，先清理最久没播放的。",
            "整首加载完就会缓存，和听了多久无关。",
            "没加载完就切歌：听过歌曲时长的 90% 会在后台下完再缓存，否则丢弃。",
            "试听片段不会缓存。",
            "缓存按账号和音质区分。换了账号或音质，原来的缓存用不上，空心箭头会消失。",
            "清理缓存不会删除下载的歌。正在播放和准备续播的缓存文件会在不再使用时释放。",
        ]),
        .init(title: "连续播放与歌词", systemImage: "music.note.list", items: [
            "播放队列会提前准备下一首，准备完成后由系统自动衔接；顺序、随机和循环播放均适用。",
            "在线播放仍可能因网络缓冲而等待；音源本身的开头或结尾静音会保留。",
            "没有可用歌词时，全屏播放器的歌词按钮会变灰且不可点；切到无歌词的歌曲时回到封面。",
            "可以在歌曲菜单中导入本地歌词，导入后重新检测。",
        ]),
        .init(title: "下载", systemImage: "square.and.arrow.down", items: [
            "下载的专辑和播放列表完成后自动加入资料库。",
            "并行下载数量同时限制下载和音频处理。调低后，已开始的下载会继续，之后按新数量排队。",
            "删除下载只删除这台手机上的音频文件，账号里的收藏不受影响，删除后无法撤销。",
        ]),
        .init(title: "网易云音质", systemImage: "waveform", items: [
            "播放、缓存和下载使用同一音质。",
            "选的音质不可用时，自动尝试较低的音质。",
            "更改音质会保留播放进度，重新加载当前歌曲。",
        ]),
        .init(title: "本地音乐", systemImage: "folder", items: [
            "把音乐放进「文件 › 我的 iPhone › NeoDizzy」，资料库会自动扫描。",
            "专辑按文件夹归类。",
            "专辑找不到时，可能已被移动或删除，下拉资料库重新扫描。",
        ]),
        .init(title: "音乐标签", systemImage: "tag", items: [
            "编辑标签只修改音频文件里的内嵌标签，专辑仍按文件夹归类。",
            "留空的字段会删除对应标签。",
            "批量编辑只支持 FLAC 文件。已保存的曲目不会重复写入；要改其他字段，关闭后重新打开批量编辑。",
            "正在播放的文件无法保存，需要先停止播放，暂停不够。",
        ]),
        .init(title: "备份与恢复", systemImage: "externaldrive", items: [
            "备份保存在「文件 › 我的 iPhone › NeoDizzy › Backup」。",
            "卸载 App 前，把 Backup 文件夹复制出来；重装后放回原处，再点「导入备份」。",
            "导入只会添加，不会删除现有的喜欢和收藏。",
            "本地专辑和播放列表来自音乐文件，需要另外把文件放回。",
            "自动备份到期后，在打开 App 或切到后台时覆盖 Backup 里的备份。备份不联网读取在线播放列表的歌曲列表。",
            "Backup 里有还没导入的旧备份时，自动备份会暂停，直到导入它或手动「立即备份」。覆盖未导入的备份后无法恢复其中的内容。",
            "打开「备份平台登录状态」后，会备份已启用平台的登录凭据；导入后是否可用取决于凭据有效期。备份文件可能被用于登录相应账号，请勿分享。",
            "「导出资料库配置」导出喜欢、收藏、在线专辑和播放列表、本地播放列表及歌曲列表，以及外观、主题、模块顺序等设置。文件不含音频和登录信息，可以分享。",
            "导出前会联网读取在线专辑和播放列表的歌曲列表，读取不完整的会在文件里标记。换签名重装请用「导入备份」。",
        ]),
        .init(title: "账号与购买", systemImage: "person.crop.circle", items: [
            "各平台独立登录，登录凭据分别保存在本机钥匙串中，仅发送给所属平台的服务。退出一个平台的账号不会退出其他平台。",
            "以下购买说明适用于 DizzyLab 模块。",
            "登录 DizzyLab 后可以收听已购专辑的完整版，查看已购专辑和关注动态。",
            "DizzyLab 密码只用于这一次登录，不会保存。登录后的会话保存在本机钥匙串中，只发送给 DizzyLab。",
            "没买的专辑播放的是试听片段，购买后可收听完整版并下载。",
            "购买会打开 DizzyLab 收银台，用支付宝付款，返回后自动核验。",
            "付款后到账可能稍有延迟。确认前请勿重复付款，稍后也可以在「已购买」里继续核验。",
            "在 App 里取消不会取消网站订单，也不会退款。",
        ]),
        .init(title: "外观与导航", systemImage: "paintpalette", items: [
            "沉浸模式会隐藏屏幕顶部的时间、电量和信号。",
            "播放页始终使用深色。",
            "每个标签页使用对应来源的颜色：DizzyLab 金色、网易云音乐红色、QQ 音乐绿色，其余页面为黑色。",
            "标签显示开关只控制入口是否可见，至少保留一个入口。拖动右侧手柄调整顺序。",
            "隐藏的模块不显示搜索结果，重新显示后保留原来的排序。平台服务可在模块设置中单独关闭。",
            "歌词默认在播放页中部高亮当前行，并避开歌曲信息和底部控制。",
        ]),
    ]
}

struct ManualView: View {
    var body: some View {
        List(ManualTopic.all) { topic in
            NavigationLink(value: AppRoute.page { ManualTopicView(topic: topic) }) {
                Label(topic.title, systemImage: topic.systemImage)
            }
            .listRowBackground(DizzyPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ManualTopicView: View {
    let topic: ManualTopic
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(topic.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(DizzyPalette.mutedText)
                        Text(item)
                    }
                }
            }
            .font(.body)
            .foregroundStyle(DizzyPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
