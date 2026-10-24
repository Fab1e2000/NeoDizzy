import SwiftUI

/// App 主体固定浅色，主题色跟随各标签页的来源。
struct AppearanceSettingsView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("模式", value: "浅色")
            } header: {
                Text("外观")
            } footer: {
                Text("应用固定使用浅色外观，全屏播放器保留深色背景。每个标签页使用对应来源的主题色。")
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
