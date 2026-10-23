import SwiftUI
import UIKit
import WebKit

/// 每个订单保留同一 View 身份；创建时只加载一次，SwiftUI 更新不会重新下单。
struct CheckoutWebView: UIViewRepresentable {
    let checkoutURL: URL
    let credentials: DizzyCredentials.Snapshot
    var onEvent: (CheckoutWebEvent) -> Void

    func makeCoordinator() -> CheckoutWebCoordinator {
        CheckoutWebCoordinator(onEvent: onEvent)
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

    static func dismantleUIView(_ webView: WKWebView, coordinator: CheckoutWebCoordinator) {
        coordinator.stop(webView)
    }
}
