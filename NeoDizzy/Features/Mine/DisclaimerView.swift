import SwiftUI

/// 应用内的多平台使用与账号说明。
struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("NeoDizzy 是非官方的开源第三方音乐客户端，与接入的音乐平台及其运营方不存在隶属、合作或授权关系。")
                Text("本项目出于学习与研究目的开发，各平台模块通过相应平台提供的页面和接口获取信息。平台变化可能导致相关功能失效。")
                Text("各平台的账号凭据分别保存在本机钥匙串中，仅发送给所属平台的服务。开启「备份平台登录状态」后，登录凭据也会写入备份文件，请妥善保管。")
                Text("请支持并尊重创作者：购买后下载的作品仅供个人使用，不要上传发布到任何公开的网络空间（包括免费作品）。")
                Text("本项目按 GPLv3 许可证提供，不附带任何担保；使用本项目产生的风险由使用者自行承担。")
            }
            .font(.body)
            .foregroundStyle(DizzyPalette.text)
            .padding(20)
        }
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("免责声明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
