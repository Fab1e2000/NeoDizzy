import SwiftUI

struct TabSettingsView: View {
    @Environment(ModuleSettings.self) private var settings
    @Environment(ModuleRegistry.self) private var modules
    var body: some View {
        List {
            Section {
                ForEach(settings.order) { tab in visibilityToggle(tab) }
                    .onMove { offsets, destination in
                        var order = settings.order
                        order.move(fromOffsets: offsets, toOffset: destination)
                        settings.reorder(order)
                    }
            } header: { Text("模块") }
            Section { Button("恢复默认") { settings.reset() } }
        }
        .environment(\.editMode, .constant(.active))
        .safeAreaPadding(.top, 5)
        .navigationTitle("模块管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func visibilityToggle(_ tab: ModuleID) -> some View {
        Toggle(isOn: Binding(get: { settings.isVisible(tab) }, set: { settings.setVisible($0, for: tab) })) {
            if let descriptor = modules.descriptor(for: tab) {
                Label(descriptor.title, systemImage: descriptor.systemImage)
            }
        }
        .disabled(!settings.canHide(tab))
    }
}

/// 搜索顺序独立于模块入口顺序保存。
struct SearchOrderSettingsView: View {
    @Environment(ModuleSettings.self) private var settings
    @Environment(ModuleRegistry.self) private var modules

    var body: some View {
        List {
            Section {
                ForEach(settings.searchOrder) { id in
                    if let descriptor = modules.descriptor(for: id) {
                        Label(descriptor.title + (settings.isVisible(id) ? "" : "（已隐藏）"),
                              systemImage: descriptor.systemImage)
                    }
                }
                .onMove { offsets, destination in
                    var order = settings.searchOrder
                    order.move(fromOffsets: offsets, toOffset: destination)
                    settings.reorderSearch(order)
                }
            }
            Section { Button("恢复默认") { settings.resetSearchOrder() } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("搜索板块排序")
        .navigationBarTitleDisplayMode(.inline)
    }
}
