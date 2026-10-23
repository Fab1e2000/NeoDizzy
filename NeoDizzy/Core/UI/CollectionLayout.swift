import SwiftUI

enum DizzyGrid {
    static let columns = [
        GridItem(.flexible(), spacing: 14, alignment: .top),
        GridItem(.flexible(), spacing: 14, alignment: .top),
    ]
}

/// 分区标题。
struct SectionHeading: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(DizzyPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
