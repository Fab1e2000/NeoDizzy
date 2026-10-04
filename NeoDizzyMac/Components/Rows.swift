import SwiftUI

/// 社团一行：封面、名称、简介和最近几张作品。社团列表和搜索结果共用。
struct LabelRow: View {
    let name: String
    let coverURL: URL?
    var description: String = ""
    var recentDiscs: [DiscSummary] = []
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: AppRoute.label(name: name)) {
            HStack(alignment: .top, spacing: 14) {
                AvatarImage(url: coverURL, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.headline).lineLimit(1)
                    if !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !recentDiscs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(recentDiscs.prefix(5)) { disc in
                                ArtworkImage(url: disc.coverURL, cornerRadius: 4)
                                    .frame(width: 34, height: 34)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(10)
            .background(.primary.opacity(isHovering ? 0.06 : 0.03), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// 用户头像与昵称。
struct UserChip: View {
    let user: CommunityUser
    var size: CGFloat = 64

    var body: some View {
        NavigationLink(value: AppRoute.user(id: user.id)) {
            VStack(spacing: 6) {
                AvatarImage(url: user.avatarURL, size: size)
                Text(user.name)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(width: size + 30)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 短评、repo 里的用户链接：小头像加强调色昵称。
struct UserLink: View {
    let user: CommunityUser

    var body: some View {
        NavigationLink(value: AppRoute.user(id: user.id)) {
            HStack(spacing: 8) {
                AvatarImage(url: user.avatarURL, size: 24)
                Text(user.name).fontWeight(.semibold).foregroundStyle(DizzyPalette.info)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
