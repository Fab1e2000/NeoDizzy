import Combine
import SwiftUI
import WebKit

/// 购买与 BOOST：原生的价格、追加支持和附言表单，确认后在收银台付款，返回后核验到账。
/// 流程与 iOS 的 PurchaseView 相同，复用 `PurchaseSheetModel` 和 `PurchaseStore`。
struct PurchaseSheet: View {
    let summary: DiscSummary
    @Environment(AccountStore.self) private var account
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var model = PurchaseSheetModel()
    @State private var showStopConfirmation = false
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !account.isLoggedIn || account.isSessionExpired || model.requiresLogin {
                        loginPrompt
                    } else if let pending = purchases.current {
                        paymentStatus(pending)
                    } else if model.isLoading {
                        ProgressView("正在读取最新价格…").frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let offer = model.offer {
                        priceForm(offer)
                    } else {
                        FailureView(message: model.failure ?? String(localized: "暂时无法购买这张专辑。"), webURL: DizzyURL.disc(summary.id)) {
                            await model.load(discID: summary.id, account: account)
                        }
                    }
                }
                .padding(22)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") {
                    if purchases.state == .confirmed { purchases.forget() }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 480, height: 560)
        .task(id: account.account?.userID) {
            if purchases.current != nil { await purchases.check() }
            else { await model.load(discID: summary.id, account: account) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
            model.reset()
            Task {
                if purchases.current != nil { await purchases.check() }
                else { await model.load(discID: summary.id, account: account) }
            }
        }
        .onDisappear {
            if model.checkout == nil {
                model.reset()
                if purchases.state == .confirmed { purchases.forget() }
            }
        }
        .sheet(isPresented: $showLogin) { LoginSheet() }
        .sheet(item: $model.checkout, onDismiss: { Task { await purchases.check() } }) { session in
            CheckoutSheet(session: session)
        }
        .alert("停止跟踪这笔付款？", isPresented: $showStopConfirmation) {
            Button("继续核验", role: .cancel) {}
            Button("停止跟踪", role: .destructive) {
                purchases.forget()
                Task { await model.load(discID: summary.id, account: account) }
            }
        } message: {
            Text("这不会取消网站订单或退款。如果已经付款，请先查看全部订单，避免重复支付。")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkImage(url: summary.coverURL, cornerRadius: 8).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.offer?.kind == .boost ? "BOOST 支持" : "购买专辑").font(.callout).foregroundStyle(.secondary)
                Text(summary.title).font(.title3.bold()).lineLimit(2)
                if let label = summary.labelName { Text(label).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(account.isSessionExpired || model.requiresLogin ? "登录已过期，请重新登录后购买。" : "登录 DizzyLab 后即可购买或追加支持。")
                .foregroundStyle(.secondary)
            Button("登录…") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func priceForm(_ offer: PurchaseOffer) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(offer.kind == .boost ? "追加金额，支持创作者" : "选择你愿意支付的金额").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥").font(.title)
                    TextField("金额", text: $model.amountText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .textFieldStyle(.plain)
                }
                Text("最低 ¥\(offer.minimum.text)").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach([1, 5, 10, 50], id: \.self) { increment in
                        Button("+\(increment)") {
                            if let amount = (PurchaseAmount(text: model.amountText) ?? offer.minimum).adding(yuan: increment) {
                                model.amountText = amount.text
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("增加 \(increment) 元")
                    }
                }
                if let amount = PurchaseAmount(text: model.amountText), let percent = offer.boostPercentage(amount: amount) {
                    Text("BOOST \(percent)%").font(.headline.monospacedDigit()).foregroundStyle(Color.dizzyAccent)
                }
            }
            .padding(16)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("附言").font(.headline)
                    Spacer()
                    Text("\(model.comment.utf16.count)/\(offer.commentLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(model.comment.utf16.count > offer.commentLimit ? DizzyPalette.danger : .secondary)
                }
                TextField("想对创作者说的话（可选）", text: $model.comment, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
            }
            if let message = model.failure ?? validationMessage(offer) {
                Text(message).foregroundStyle(Color.dizzyAccent)
            }
            Button {
                Task { await model.prepare(summary: summary, account: account, purchases: purchases) }
            } label: {
                HStack {
                    if model.isPreparing { ProgressView().controlSize(.small) }
                    Text(model.isPreparing ? "正在准备…" : checkoutTitle(offer))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isPreparing || validationMessage(offer) != nil)
            Text("将打开 DizzyLab 收银台，使用支付宝付款（可用手机支付宝扫码）。完成后会自动核验结果。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .disabled(model.isPreparing)
    }

    private func validationMessage(_ offer: PurchaseOffer) -> String? {
        do { _ = try offer.validate(amountText: model.amountText, comment: model.comment); return nil }
        catch { return error.localizedDescription }
    }

    private func checkoutTitle(_ offer: PurchaseOffer) -> String {
        guard let amount = PurchaseAmount(text: model.amountText) else { return String(localized: "使用支付宝付款") }
        return amount.cents == 0 ? String(localized: "免费领取") : String(localized: "支付宝付款 ¥\(amount.text)")
    }

    private func paymentStatus(_ pending: PendingPurchase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if purchases.state == .checking {
                ProgressView("正在核验付款结果…")
            } else {
                Label(purchases.state == .confirmed ? "已确认到账" : "等待付款确认",
                      systemImage: purchases.state == .confirmed ? "checkmark.seal.fill" : "clock")
                    .font(.title3.bold())
                    .foregroundStyle(purchases.state == .confirmed ? DizzyPalette.success : Color.dizzyAccent)
            }
            Text("\(pending.title) · ¥\(pending.attempt.amount.text)")
            if purchases.state == .confirmed {
                Text(pending.attempt.kind == .boost ? "感谢你对创作者的追加支持。" : "专辑已加入「已购买」，可以收听完整版和下载。")
                    .foregroundStyle(.secondary)
            } else {
                Text("如果已完成支付，到账可能稍有延迟。尚未确认前，请勿重复付款；稍后也可从「已购买」继续核验。")
                    .foregroundStyle(.secondary)
                if let failure = purchases.failure { Text(failure).foregroundStyle(Color.dizzyAccent) }
                HStack {
                    Button("我已付款，重新核验") { Task { await purchases.check() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchases.state == .checking)
                    if purchases.requiresLogin {
                        Button("重新登录…") { showLogin = true }
                    }
                }
                Link("查看网站已付订单", destination: DizzyURL.page(pending.attempt.kind == .boost ? "/albums/purchases/boost/" : "/albums/purchases/"))
                Button("停止跟踪这笔付款", role: .destructive) { showStopConfirmation = true }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 支付宝收银台。Mac 没有支付宝 App，使用网页收银台：用手机支付宝扫码，或登录支付宝账户付款。
private struct CheckoutSheet: View {
    let session: CheckoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseStore.self) private var purchases
    @State private var isLoading = true
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("支付宝收银台").font(.headline)
                if isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button("关闭") { dismiss() }
                Button("我已付款") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            if let message = failure ?? notice {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(failure == nil ? Color.secondary : Color.dizzyAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            CheckoutWebView(checkoutURL: session.url, credentials: session.credentials) { event in
                switch event {
                case .loadingChanged(let loading): isLoading = loading
                case .siteReturned: dismiss()
                case .openedAlipay: break
                case .manualReturnNeeded, .alipayAppUnavailable:
                    notice = String(localized: "Mac 上没有支付宝 App：请在此页面用手机支付宝扫码，或登录支付宝账户付款。完成后点「我已付款」核验到账。")
                case .failed(let message): failure = message; isLoading = false
                }
            }
            .id(session.id)
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 640, idealHeight: 720)
        .onChange(of: purchases.state) { _, state in
            if state == .confirmed { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in dismiss() }
    }
}

/// 收银台 WebView。每笔订单保留同一个视图身份，SwiftUI 更新不会重新下单。
private struct CheckoutWebView: NSViewRepresentable {
    let checkoutURL: URL
    let credentials: DizzyCredentials.Snapshot
    var onEvent: (CheckoutWebEvent) -> Void

    /// 使用桌面版 Safari 标识，网站和支付宝会提供适合电脑的扫码收银台。
    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

    func makeCoordinator() -> CheckoutWebCoordinator {
        CheckoutWebCoordinator(onEvent: onEvent)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.start(webView, checkoutURL: checkoutURL, credentials: credentials)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: CheckoutWebCoordinator) {
        coordinator.stop(webView)
    }
}
