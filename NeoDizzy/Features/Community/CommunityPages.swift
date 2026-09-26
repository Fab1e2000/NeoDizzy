import SwiftUI

struct SupporterRankingView: View {
    @State private var state = Loadable { try await DizzyCommunity.shared.ranking() }
    var body: some View {
        LoadableContent(state: state, webURL: DizzyURL.page("/ranking/")) { supporters in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("感谢每一位支持音乐创作的人。")
                        .font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                    ForEach(supporters) { supporter in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(supporter.rank)).font(.title3.bold().monospacedDigit())
                                .foregroundStyle(supporter.rank <= 3 ? DizzyPalette.accent : DizzyPalette.mutedText)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 8) {
                                CommunityUserLink(user: supporter.user)
                                if !supporter.bio.isEmpty { Text(supporter.bio).font(.caption).foregroundStyle(DizzyPalette.mutedText) }
                            }
                        }
                        Divider()
                    }
                }.padding(20)
            }.refreshable { await state.load() }
        }
        .navigationTitle("支持者榜").navigationBarTitleDisplayMode(.inline).dizzyPageBackground()
    }
}

@Observable
final class CommunityProfileModel {
    let userID: Int
    var section: ProfileSection = .music
    var profile: CommunityProfile?
    var failure: String?
    var loading = false
    var page = 0
    var discs: [DiscSummary] = []
    var labels: [SearchLabel] = []
    var reviews: [ReviewSummary] = []
    private var generation = 0
    init(userID: Int) { self.userID = userID }
    func reset() async {
        generation += 1
        loading = false; page = 0; profile = nil; discs = []; labels = []; reviews = []; failure = nil
        await next()
    }
    func next() async {
        guard !loading else { return }
        loading = true; failure = nil
        let gen = generation
        do {
            let result = try await DizzyCommunity.shared.profile(userID, section: section, page: page + 1)
            try Task.checkCancellation()
            guard gen == generation else { return }
            profile = result; page += 1
            var ids = Set(discs.map(\.id)); discs += result.discs.filter { ids.insert($0.id).inserted }
            var names = Set(labels.map(\.id)); labels += result.labels.filter { names.insert($0.id).inserted }
            var rids = Set(reviews.map(\.id)); reviews += result.reviews.filter { rids.insert($0.id).inserted }
        } catch is CancellationError {} catch { if gen == generation { failure = error.localizedDescription } }
        if gen == generation { loading = false }
    }
}
struct CommunityProfileView: View {
    @State private var model: CommunityProfileModel
    init(userID: Int) { _model = State(initialValue: CommunityProfileModel(userID: userID)) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let profile = model.profile {
                    HStack(alignment: .top, spacing: 16) {
                        ArtworkImage(url: profile.user.avatarURL, cornerRadius: 16).frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.user.name).font(.title2.bold())
                            Text(profile.joined).font(.caption).foregroundStyle(DizzyPalette.mutedText)
                            if !profile.bio.isEmpty { Text(profile.bio).font(.subheadline).textSelection(.enabled) }
                        }
                    }
                }
                Picker("用户内容", selection: $model.section) {
                    ForEach(ProfileSection.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if model.section == .following {
                    ForEach(model.labels) { label in
                        NavigationLink(value: AppRoute.label(name: label.name)) {
                            HStack(spacing: 14) {
                                ArtworkImage(url: label.coverURL, cornerRadius: 10).frame(width: 56, height: 56)
                                Text(label.name).font(.headline)
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }
                        }.buttonStyle(.plain)
                    }
                } else if model.section == .review {
                    ForEach(model.reviews) { ReviewRow(review: $0) }
                } else { DiscGrid(discs: model.discs) }
                if let failure = model.failure {
                    LoadFailureView(message: failure, webURL: DizzyURL.page("/u/\(model.userID)/\(model.section.rawValue)/")) { await model.next() }
                } else if model.loading { ProgressView().frame(maxWidth: .infinity) }
                else if model.profile?.hasMore == true {
                    Button("加载更多") { Task { await model.next() } }.frame(maxWidth: .infinity)
                } else if model.profile != nil && model.discs.isEmpty && model.labels.isEmpty && model.reviews.isEmpty {
                    Text("这里还没有内容。").foregroundStyle(DizzyPalette.mutedText).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }.padding(20)
        }
        .navigationTitle("用户主页").navigationBarTitleDisplayMode(.inline).dizzyPageBackground()
        .task(id: model.section) { await model.reset() }
        .refreshable { await model.reset() }
    }
}

struct ShuffleDiscoveryView: View {
    @Environment(PlayerStore.self) private var player
    @State private var state = Loadable { try await DizzyCommunity.shared.shuffle() }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("下一首，会遇见什么？").font(.title2.bold()).padding(.top, 12)
                LoadableContent(state: state, webURL: DizzyURL.page("/shuffle/")) { selection in
                    VStack(spacing: 16) {
                        ArtworkImage(url: selection.track.coverURL, cornerRadius: 20).frame(maxWidth: 280)
                        Text(selection.track.title).font(.title2.bold()).multilineTextAlignment(.center)
                        NavigationLink(selection.track.albumTitle, value: AppRoute.disc(id: selection.track.discID)).font(.headline)
                        NavigationLink(selection.label, value: AppRoute.label(name: selection.label)).font(.subheadline)
                        if DizzyURL.isPreviewStream(selection.stream) { Text("试听片段").font(.caption).foregroundStyle(DizzyPalette.mutedText) }
                        if !selection.tags.isEmpty { Text(selection.tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(DizzyPalette.mutedText) }
                        Button {
                            player.playDiscovery(selection)
                        } label: { Label("播放这首", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                Button { Task { await state.load() } } label: {
                    Label(state.isLoading ? "正在寻找…" : "换一首", systemImage: "shuffle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large).disabled(state.isLoading)
                Text("播放后可用播放器的上一首回听，下一首获取新的随机曲目。")
                    .font(.caption).foregroundStyle(DizzyPalette.mutedText)
            }.padding(24)
        }.navigationTitle("随便听听").navigationBarTitleDisplayMode(.inline).dizzyPageBackground()
    }
}
