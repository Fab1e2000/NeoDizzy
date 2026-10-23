import SwiftUI

/// 可折叠的长文本：默认显示前几行，被截断时右下角出现「更多」，与 App Store 的介绍相同。
/// 带标题的简介，全文直接展开，不折叠。
struct ExpandableText: View {
    let title: LocalizedStringKey
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: title)
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
