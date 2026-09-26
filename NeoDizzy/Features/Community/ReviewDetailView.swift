import SwiftUI
import NukeUI

struct ReviewDetailView: View {
    let id: Int
    @State private var state: Loadable<ReviewDetail>
    init(id: Int) {
        self.id = id
        _state = State(initialValue: Loadable {
            let html = try await DizzyHTTPClient.shared.html(path: "/review/\(id)/")
            return try CommunityPageParser.review(html)
        })
    }
    var body: some View {
        LoadableContent(state: state, webURL: DizzyURL.page("/review/\(id)/")) { review in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(review.title).font(.title2.bold()).textSelection(.enabled)
                    if let user = review.user { CommunityUserLink(user: user) }
                    Text(review.text).font(.body).lineSpacing(6).textSelection(.enabled)
                    ForEach(review.images, id: \.self) { url in
                        LazyImage(url: url) { state in
                            if let image = state.image { image.resizable().scaledToFit() }
                            else if state.error != nil { Label("图片加载失败", systemImage: "photo").foregroundStyle(DizzyPalette.mutedText) }
                            else { ProgressView().frame(maxWidth: .infinity).padding(30) }
                        }
                    }
                    Link("在网页查看回复", destination: DizzyURL.page("/review/\(id)/")).font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.refreshable { await state.load() }
        }.navigationTitle("repo 长评").navigationBarTitleDisplayMode(.inline).dizzyPageBackground()
    }
}
