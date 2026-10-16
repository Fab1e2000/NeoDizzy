import SwiftUI

/// 外观（跟随系统、浅色、深色）与主题色。换主题色后桌面图标同步更换。
struct AppearanceSettingsView: View {
    @Environment(ThemeIconController.self) private var themeIcon
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

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
                Text("播放页始终使用深色。")
            }
            .listRowBackground(DizzyPalette.surface)

            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppTheme.presets) { theme in
                        swatch(theme, isSelected: theme.id == settings.themeID) {
                            settings.themeID = theme.id
                        }
                    }
                }
                .padding(.vertical, 8)
                if let message = themeIcon.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message).font(.footnote).foregroundStyle(DizzyPalette.mutedText)
                        Button("重试更新桌面图标") {
                            Task { await themeIcon.apply(theme: settings.theme) }
                        }
                    }
                }
                if settings.themeID != AppTheme.defaultID {
                    Button("恢复默认（\(AppTheme.selected(AppTheme.defaultID).name)）") {
                        settings.themeID = AppTheme.defaultID
                    }
                }
            } header: {
                Text("主题色 · \(settings.theme.name)")
            } footer: {
                Text("桌面图标会换成同色的版本，并跟随主屏幕的浅色、深色外观切换。")
            }
            .listRowBackground(DizzyPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("外观与主题")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ theme: AppTheme, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(theme.onColor)
                        }
                    }
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(isSelected ? theme.color : .clear, lineWidth: 2)
                    }
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? DizzyPalette.text : DizzyPalette.mutedText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
