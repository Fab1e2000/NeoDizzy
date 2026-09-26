import SwiftUI
import UIKit
import WebKit

enum CheckoutWebEvent {
    case loadingChanged(Bool)
    /// 只提示调用方重新查询到账状态，不能直接标记成功。
    case siteReturned
    case openedAlipay
    case manualReturnNeeded
    case failed(String)
}

/// 每个订单保留同一 View 身份；创建时只加载一次，SwiftUI 更新不会重新下单。
struct CheckoutWebView: UIViewRepresentable {
    let checkoutURL: URL
    let credentials: DizzyCredentials.Snapshot
    var onEvent: (CheckoutWebEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = DizzyHTTPClient.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        context.coordinator.start(webView, checkoutURL: checkoutURL, credentials: credentials)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onEvent: (CheckoutWebEvent) -> Void
        private var setupTask: Task<Void, Never>?
        private var isActive = true
        private var isOpeningAlipay = false

        init(onEvent: @escaping (CheckoutWebEvent) -> Void) {
            self.onEvent = onEvent
        }

        func start(_ webView: WKWebView, checkoutURL: URL, credentials: DizzyCredentials.Snapshot) {
            setupTask = Task { [weak self, weak webView] in
                guard let self, let webView, self.isActive else { return }
                guard CheckoutNavigationPolicy.isCheckoutURL(checkoutURL) else {
                    self.report(.failed("付款地址无效，请关闭后重新打开购买面板。"))
                    return
                }
                self.report(.loadingChanged(true))
                // WebKit 的 Cookie 写入是异步的，全部完成后才能访问会创建订单的地址。
                for cookie in CheckoutNavigationPolicy.cookies(from: credentials) {
                    guard !Task.isCancelled, self.isActive else { return }
                    await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
                guard !Task.isCancelled, self.isActive else { return }
                var request = URLRequest(url: checkoutURL, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue(DizzyURL.site.absoluteString + "/", forHTTPHeaderField: "Referer")
                // 不手工设置 Cookie 请求头；WebKit 只向对应域名发送会话 Cookie。
                webView.load(request)
            }
        }

        func stop(_ webView: WKWebView) {
            isActive = false
            setupTask?.cancel()
            setupTask = nil
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            onEvent = { _ in }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard isActive, let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            switch CheckoutNavigationPolicy.decision(for: url, isMainFrame: isMainFrame) {
            case .allow:
                decisionHandler(.allow)
            case .openAlipay:
                decisionHandler(.cancel)
                openAlipay(url)
            case .block:
                decisionHandler(.cancel)
                if isMainFrame {
                    report(.loadingChanged(false))
                    report(.failed("收银台跳转到了不支持的地址。请关闭页面后检查到账状态。"))
                }
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard isActive, navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                return nil
            }
            // target=_blank 的 H5 链接沿用当前收银台，保留当前隔离 Cookie 容器。
            switch CheckoutNavigationPolicy.decision(for: url) {
            case .allow: webView.load(navigationAction.request)
            case .openAlipay: openAlipay(url)
            case .block: break
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            report(.loadingChanged(true))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            report(.loadingChanged(false))
            if let url = webView.url, CheckoutNavigationPolicy.isSiteReturn(url) {
                report(.siteReturned)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            report(.loadingChanged(false))
            report(.failed("收银台已中断，请关闭页面后检查到账状态。"))
            // 不自动 reload：重新请求 checkout 会创建另一笔订单。
        }

        private func openAlipay(_ url: URL) {
            guard isActive, !isOpeningAlipay else { return }
            isOpeningAlipay = true
            report(.loadingChanged(false))
            let routedURL = AlipayReturnRouter.paymentURL(from: url)
            if routedURL == nil { report(.manualReturnNeeded) }
            debugLog("支付宝调起路由：\(routedURL == nil ? "网页返回" : "App 返回")")
            UIApplication.shared.open(routedURL ?? url, options: [:]) { [weak self] opened in
                guard let self else { return }
                self.isOpeningAlipay = false
                if opened {
                    self.report(.openedAlipay)
                } else {
                    self.report(.failed("无法打开支付宝。请确认已安装支付宝，或继续使用网页收银台。"))
                }
            }
        }

        private func reportFailure(_ error: Error) {
            let error = error as NSError
            // 策略拦截或交给支付宝引起的取消，不应覆盖真正的页面状态。
            guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled),
                  !(error.domain == "WebKitErrorDomain" && error.code == 102) else { return }
            report(.loadingChanged(false))
            // 不使用 localizedDescription：它可能包含签名、订单号或回调 URL。
            report(.failed("收银台暂时无法加载，请关闭页面后检查到账状态。"))
        }

        private func report(_ event: CheckoutWebEvent) {
            guard isActive else { return }
            onEvent(event)
        }
    }
}
