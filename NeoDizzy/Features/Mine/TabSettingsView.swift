import SwiftUI

struct TabSettingsView: View {
    @Environment(AppServices.self) private var services
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
            Section {
                ForEach(services.registrations.filter(\.canDisable), id: \.descriptor.id) { registration in
                    Toggle(registration.descriptor.title, isOn: Binding(
                        get: { services.isEnabled(registration.descriptor.id) },
                        set: { value in Task { await services.setEnabled(value, for: registration.descriptor.id) } }
                    ))
                    .disabled(services.transitioning.contains(registration.descriptor.id))
                }
            } header: { Text("平台服务") } footer: {
                Text("关闭平台服务会停止该平台的在线播放、同步与未完成下载。账号凭据、资料库记录和已下载文件保留；上方开关只控制入口显示。")
            }
            Section { Button("恢复默认显示") { settings.reset() } }
        }
        .environment(\.editMode, .constant(.active))
        .safeAreaPadding(.top, 5)
        .navigationTitle("模块管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func visibilityToggle(_ tab: ModuleID) -> some View {
        Toggle(isOn: Binding(get: { settings.isVisible(tab) }, set: { settings.setVisible($0, for: tab) })) {
            if let descriptor = modules.descriptor(for: tab) {
                Label { Text(descriptor.title) } icon: { descriptor.icon }
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
                        Label {
                            Text(descriptor.title + (settings.isVisible(id) ? "" : "（已隐藏）"))
                        } icon: { descriptor.icon }
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
