import SwiftUI

/// 最近浏览：进入过的专辑详情，按最近访问排序。
struct HistoryPage: View {
    @Environment(BrowsingHistoryStore.self) private var history
    @State private var confirmingClear = false
    @State private var selection = Set<String>()

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView("暂无浏览记录", systemImage: "clock",
                                       description: Text("进入专辑页后，会在这里留下记录。仅保存在本机，保留最近 200 张专辑。"))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("最近浏览")
                        .font(.pageTitle)
                        .padding(.horizontal, PageMetrics.margin)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    historyList
                }
            }
        }
        .navigationTitle("最近浏览")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空", role: .destructive) { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
            }
        }
        .confirmationDialog("清空所有浏览记录？", isPresented: $confirmingClear) {
            Button("清空浏览记录", role: .destructive) { history.clear() }
        }
    }

    private var historyList: some View {
        List(selection: $selection) {
            ForEach(history.entries) { entry in
                NavigationLink(value: AppRoute.disc(id: entry.id)) {
                    HStack(spacing: 12) {
                        ArtworkImage(url: entry.coverURL, cornerRadius: 5)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                            if let label = entry.labelName, !label.isEmpty {
                                Text(label).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(entry.visitedAt, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                }
                .tag(entry.id)
                .contextMenu {
                    Button("从浏览记录中移除", systemImage: "trash") {
                        history.remove(ids: selection.contains(entry.id) ? selection : [entry.id])
                    }
                }
            }
            .onDelete { offsets in history.remove(ids: Set(offsets.map { history.entries[$0].id })) }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onDeleteCommand { history.remove(ids: selection) }
    }
}
