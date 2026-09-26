import SwiftUI

/// 控制「我的」弹层。根视图持有并放进环境，各页页头通过它打开。
@Observable
final class MinePresentation {
    var isPresented = false
}

/// 各主页面共用的页头：左侧大标题，右侧头像玻璃按钮（「我的」的入口）。登录后显示账号头像。
/// 样式沿用 NeoBili，页头是滚动内容的第一行，随内容滚走。
struct PageHeader: View {
    let title: String
    @Environment(MinePresentation.self) private var mine: MinePresentation?
    @Environment(AccountStore.self) private var account: AccountStore?

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Button { mine?.isPresented = true } label: {
                avatar
                    .frame(width: 40, height: 40)
                    .padding(2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的")
            .accessibilityHint("打开个人页面")
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = account?.account {
            ArtworkImage(url: user.avatarURL, cornerRadius: 20)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(DizzyPalette.mutedText)
        }
    }
}

/// 主页面的骨架：隐藏系统导航栏，页头作为滚动内容的第一行。
/// 内容放在 LazyVStack 里，分页底栏滚到屏幕上时才触发加载。
struct MainTabPage<Content: View>: View {
    let tab: MainTab
    var onRefresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        let page = ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageHeader(title: tab.title)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .dizzyPageBackground()

        if let onRefresh {
            page.refreshable { await onRefresh() }
        } else {
            page
        }
    }
}
