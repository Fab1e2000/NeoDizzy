import SwiftUI

/// 从播放器点作者名进入的艺人页。歌曲里只存了作者名字，没有艺人 ID，
/// 所以先显示名字占位、立刻进入页面，再在页面里请求来源解析出真正的艺人页；
/// 解析失败就留在占位页，可以重试。
struct PlayerArtistPage: View {
    let track: Track
    let name: String
    /// 这个名字在本地拆出的作者列表里的位置，名字对不上时按位置匹配。
    let index: Int
    let count: Int

    @Environment(ModuleRegistry.self) private var modules

    private enum Phase {
        case loading
        case resolved(AppRoute)
        case failed
    }

    @State private var phase = Phase.loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .resolved(let route):
                AppRouteDestination(route: route)
            case .loading, .failed:
                placeholder
            }
        }
        .task(id: attempt) { await resolve() }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(DizzyPalette.artworkPlaceholder)
                Image(systemName: "person.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(DizzyPalette.artworkPlaceholderSymbol)
            }
            .frame(width: 140, height: 140)

            Text(name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            switch phase {
            case .failed:
                Text("无法加载艺人信息")
                    .foregroundStyle(.secondary)
                Button("重试") { attempt += 1 }
                    .buttonStyle(.bordered)
            default:
                ProgressView()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolve() async {
        if case .resolved = phase { return }
        phase = .loading
        do {
            let destinations = try await modules.artistDestinations(for: track)
            guard !Task.isCancelled else { return }
            if let route = Self.match(name: name, index: index, count: count, in: destinations) {
                phase = .resolved(route)
            } else {
                phase = .failed
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    /// 先按名字找；名字对不上（拆分方式和来源不同）时，数量一致就按位置，只有一个结果就用它。
    static func match(name: String, index: Int, count: Int,
                      in destinations: [PlayerArtistDestination]) -> AppRoute? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = destinations.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }) {
            return exact.route
        }
        if destinations.count == count, destinations.indices.contains(index) {
            return destinations[index].route
        }
        return destinations.count == 1 ? destinations[0].route : nil
    }
}
