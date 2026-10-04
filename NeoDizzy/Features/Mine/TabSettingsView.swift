import SwiftUI

struct TabSettingsView: View {
    @Environment(TabSettings.self) private var settings
    var body: some View {
        List {
            Section {
                ForEach(settings.order) { tab in visibilityToggle(tab) }
                    .onMove { offsets, destination in
                        var order = settings.order
                        order.move(fromOffsets: offsets, toOffset: destination)
                        settings.reorder(order)
                    }
            } header: { Text("主页面") } footer: {
                Text("拖动右侧手柄调整顺序，至少保留一个主页面。")
            }
            Section { Button("恢复默认") { settings.reset() } }
        }
        .environment(\.editMode, .constant(.active))
        .safeAreaPadding(.top, 5)
        .navigationTitle("标签栏")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func visibilityToggle(_ tab: MainTab) -> some View {
        Toggle(isOn: Binding(get: { settings.isVisible(tab) }, set: { settings.setVisible($0, for: tab) })) {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .disabled(!settings.canHide(tab))
    }
}
