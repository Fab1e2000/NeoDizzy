import SwiftUI

/// 与仓库里的 DISCLAIMER.md 内容一致。
struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("NeoDizzy 是非官方的开源第三方客户端，与 DizzyLab 及其运营方不存在隶属、合作或授权关系。")
                Text("本项目出于学习与研究目的开发，通过 DizzyLab 网站本身提供的页面和接口获取信息。网站变化可能导致功能随时失效。")
                Text("账号凭据只保存在本机的钥匙串中，不会发送到 DizzyLab 以外的任何地方。")
                Text("请支持并尊重创作者：购买后下载的作品仅供个人使用，不要上传发布到任何公开的网络空间（包括免费作品）。")
                Text("本项目按 GPLv3 许可证提供，不附带任何担保；使用本项目产生的风险由使用者自行承担。")
            }
            .font(.body)
            .foregroundStyle(DizzyPalette.text)
            .padding(20)
        }
        .dizzyPageBackground()
        .navigationTitle("免责声明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
