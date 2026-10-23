import SwiftUI

/// 外观：跟随系统、浅色、深色。主题色跟随各标签页的来源，不再单独设置。
struct AppearanceSettingsView: View {
    var body: some View {
        @Bindable var settings = AppearanceSettings.shared
        List {
            Section {
                Picker("外观", selection: $settings.mode) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("外观")
            } footer: {
                Text("每个标签页使用对应来源的颜色，资料库与搜索为黑色。")
            }
            .listRowBackground(DizzyPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}
