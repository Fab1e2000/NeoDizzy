// Official Watchman SDK flow follows api-enhanced/register_checktoken_v2 (MIT).
// Use a real WebKit context without altering browser identity or passing account cookies.
import Foundation
import WebKit

@MainActor
final class NeteaseCheckToken: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?

    func fetch() async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.userContentController.add(self, name: "checkToken")
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.navigationDelegate = self
                webView = view
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    self?.finish(.failure(NeteaseError.checkTokenUnavailable))
                }
                view.loadHTMLString(Self.html, baseURL: URL(string: "https://music.163.com/"))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "checkToken", message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        if let token = body["token"] as? String, !token.isEmpty {
            finish(.success(token))
        } else {
            finish(.failure(NeteaseError.checkTokenUnavailable))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(NeteaseError.checkTokenUnavailable))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(NeteaseError.checkTokenUnavailable))
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "checkToken")
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation.resume(with: result)
    }

    private static let html = #"""
    <!doctype html><html><head><meta charset="UTF-8"></head><body>
    <script>
    let finished = false;
    function complete(token) {
        if (finished) return;
        finished = true;
        window.webkit.messageHandlers.checkToken.postMessage({token: typeof token === 'string' ? token : ''});
    }
    function start() {
        try {
            window.initWatchman({
                auto: true,
                productNumber: 'YD00000558929251',
                onload: function(instance) {
                    let requested = false;
                    function requestToken() {
                        if (requested || finished) return;
                        requested = true;
                        clearTimeout(readyTimeout);
                        try { instance.getToken('bd5d2f973ef74cd2a61325a412ae54d9', complete); }
                        catch (_) { complete(''); }
                    }
                    const readyTimeout = setTimeout(requestToken, 10000);
                    try { instance.getInstance().I(requestToken); }
                    catch (_) { clearTimeout(readyTimeout); complete(''); }
                },
                onerror: function() { complete(''); }
            });
        } catch (_) { complete(''); }
    }
    </script>
    <script src="https://acstatic-dun.126.net/tool.min.js" onload="start()" onerror="complete('')"></script>
    </body></html>
    """#
}
