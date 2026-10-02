import SwiftUI

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
        .safeAreaPadding(.top, 5)
        .navigationTitle("用户主页").navigationBarTitleDisplayMode(.inline).dizzyPageBackground()
        .task(id: model.section) { await model.reset() }
        .refreshable { await model.reset() }
    }
}
