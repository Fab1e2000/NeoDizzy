// Official-site login follows the same WebKit flow as NeteaseLoginView.
// The browser and its cookies belong only to this QQ Music login presentation.
import SwiftUI
import WebKit

struct QQMusicLoginView: View {
    let store: QQMusicStore
    @Environment(\.dismiss) private var dismiss
    @State private var browser = QQMusicLoginBrowser()
    @State private var loginTask: Task<Void, Never>?
    @State private var error: String?
    @State private var failedToLoad = false
    @State private var checking = false
    @State private var loadRevision = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error {
                    HStack(alignment: .firstTextBaseline) {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Spacer()
                        Button(failedToLoad ? "重新载入" : "重试") {
                            if failedToLoad { loadRevision += 1 }
                            else { startLogin() }
                        }
                            .font(.footnote)
                            .disabled(checking)
                    }.padding()
                }
                WebView(browser.page)
                    .overlay(alignment: .top) {
                        if browser.page.isLoading {
                            ProgressView(value: browser.page.estimatedProgress)
                                .progressViewStyle(.linear)
                        }
                    }
            }
            .navigationTitle("登录 QQ 音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        loginTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: startLogin) {
                        if checking {
                            ProgressView().accessibilityLabel("正在同步并验证登录状态")
                        } else {
                            Text("完成")
                        }
                    }.disabled(checking)
                }
            }
            .task(id: loadRevision) { await loadWebsite() }
            .onDisappear {
                loginTask?.cancel()
                browser.page.stopLoading()
            }
        }
    }

    private func loadWebsite() async {
        error = nil
        failedToLoad = false
        do {
            for try await _ in browser.page.load(URLRequest(url: URL(string: "https://y.qq.com/")!)) {
                try Task.checkCancellation()
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failedToLoad = true
            self.error = "官网加载失败：\(error.localizedDescription)"
        }
    }

    private func startLogin() {
        guard !checking else { return }
        checking = true
        loginTask = Task { await checkLogin() }
    }

    private func checkLogin() async {
        defer { checking = false }
        error = nil
        failedToLoad = false
        do {
            try await store.completeWebLogin(readCookies: {
                await browser.dataStore.httpCookieStore.allCookies()
            })
            try Task.checkCancellation()
            dismiss()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, store.active else { return }
            self.error = error.localizedDescription
        }
    }
}

@Observable @MainActor
private final class QQMusicLoginBrowser {
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let page: WebPage
    init() {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.defaultNavigationPreferences.preferredContentMode = .desktop
        page = WebPage(configuration: configuration)
    }
}
