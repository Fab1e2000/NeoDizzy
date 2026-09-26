import SwiftUI

struct BrowsingHistoryView: View {
    @Environment(BrowsingHistoryStore.self) private var history
    @State private var confirmingClear = false

    var body: some View {
        List {
            if history.entries.isEmpty {
                ContentUnavailableView("暂无浏览记录", systemImage: "clock.arrow.circlepath", description: Text("进入专辑详情页后，会在这里留下记录。"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(history.entries) { entry in
                        NavigationLink(value: AppRoute.disc(id: entry.id)) {
                            HStack(spacing: 12) {
                                ArtworkImage(url: entry.coverURL, cornerRadius: 10)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.headline).lineLimit(2)
                                    if let label = entry.labelName, !label.isEmpty {
                                        Text(label).font(.subheadline).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                                    }
                                    Text(entry.visitedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(DizzyPalette.mutedText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { offsets in
                        history.remove(ids: Set(offsets.map { history.entries[$0].id }))
                    }
                } footer: {
                    Text("仅保存在本机，保留最近 200 张专辑。")
                }
                .listRowBackground(DizzyPalette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .navigationTitle("浏览记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) { confirmingClear = true }
                }
            }
        }
        .confirmationDialog("清空所有浏览记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空浏览记录", role: .destructive) { history.clear() }
        }
    }
}
