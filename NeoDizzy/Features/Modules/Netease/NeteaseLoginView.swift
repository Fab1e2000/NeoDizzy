// Official-site login follows MeloX NeteaseLoginView (GPL-3.0); cookies remain module-local.
import SwiftUI
import WebKit

struct NeteaseLoginView: View {
    let store: NeteaseStore
    @State private var browser = LoginBrowser()
    @State private var loginTask: Task<Void, Never>?
    @State private var error: String?
    @State private var checking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding() }
                WebView(browser.page)
            }
            .navigationTitle("登录网易云音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { loginTask = Task { await checkLogin() } }.disabled(checking)
                }
            }
            .onDisappear { loginTask?.cancel() }
            .task { browser.page.load(URLRequest(url: URL(string: "https://music.163.com/#")!)) }
        }
    }
    private func checkLogin() async {
        checking = true
        defer { checking = false }
        let cookies = await browser.dataStore.httpCookieStore.allCookies()
        let allowed = cookies.filter {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return ["music.163.com", "163.com"].contains(domain) && ["MUSIC_U", "__csrf"].contains($0.name)
        }
        guard allowed.contains(where: { $0.name == "MUSIC_U" }) else { error = "请先在官网完成登录，再点完成。"; return }
        do { try await store.login(cookie: allowed.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

@Observable
private final class LoginBrowser {
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let page: WebPage
    init() {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.defaultNavigationPreferences.preferredContentMode = .desktop
        page = WebPage(configuration: configuration)
    }
}
