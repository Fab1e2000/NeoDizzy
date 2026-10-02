import SwiftUI

struct PurchaseView: View {
    let summary: DiscSummary
    @Environment(AccountStore.self) private var account
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var model = PurchaseSheetModel()
    @State private var showLogin = false
    @State private var showStopConfirmation = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    albumHeader
                    if !account.isLoggedIn || account.isSessionExpired || model.requiresLogin {
                        loginPrompt
                    } else if let pending = purchases.current {
                        paymentStatus(pending)
                    } else if model.isLoading {
                        ProgressView("正在读取最新价格…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let offer = model.offer {
                        priceForm(offer)
                    } else {
                        LoadFailureView(message: model.failure ?? "暂时无法购买这张专辑。", webURL: DizzyURL.disc(summary.id)) {
                            await model.load(discID: summary.id, account: account)
                        }
                    }
                }
                .padding(20)
            }
            .dizzyPageBackground()
            .navigationTitle(model.offer?.kind == .boost ? "BOOST 支持" : "购买专辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if purchases.state == .confirmed { purchases.forget() }
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
            .task(id: account.account?.userID) {
                if purchases.current != nil {
                    await purchases.check()
                } else {
                    await model.load(discID: summary.id, account: account)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
                model.reset()
                Task {
                    if purchases.current != nil { await purchases.check() }
                    else { await model.load(discID: summary.id, account: account) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyPaymentReturned)) { _ in
                model.checkout = nil
            }
            .onDisappear {
                if model.checkout == nil {
                    model.reset()
                    if purchases.state == .confirmed { purchases.forget() }
                }
            }
            .sheet(isPresented: $showLogin) {
                NavigationStack {
                    LoginView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showLogin = false } } }
                }
            }
            .fullScreenCover(item: $model.checkout, onDismiss: {
                Task { await purchases.check() }
            }) { session in
                CheckoutView(session: session)
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
        .tint(DizzyPalette.accent)
        .preferredColorScheme(.dark)
    }

    private var albumHeader: some View {
        HStack(spacing: 14) {
            ArtworkImage(url: summary.coverURL, cornerRadius: 10)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title).font(.headline)
                if let label = summary.labelName {
                    Text(label).font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(account.isSessionExpired || model.requiresLogin ? "登录已过期，请重新登录后购买。" : "登录 DizzyLab 后即可购买或追加支持。")
                .foregroundStyle(DizzyPalette.mutedText)
            Button("登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func priceForm(_ offer: PurchaseOffer) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(offer.kind == .boost ? "追加金额，支持创作者" : "选择你愿意支付的金额")
                .font(.title3.bold())
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("¥").font(.title2)
                    TextField("金额", text: $model.amountText)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .accessibilityIdentifier("purchase.amount")
                }
                Text("最低 ¥\(offer.minimum.text)")
                    .font(.caption).foregroundStyle(DizzyPalette.mutedText)
                HStack(spacing: 10) {
                    ForEach([1, 5, 10, 50], id: \.self) { increment in
                        Button("+\(increment)") {
                            if let amount = (PurchaseAmount(text: model.amountText) ?? offer.minimum).adding(yuan: increment) {
                                model.amountText = amount.text
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("增加 \(increment) 元")
                    }
                }
                if let amount = PurchaseAmount(text: model.amountText), let percent = offer.boostPercentage(amount: amount) {
                    Text("BOOST \(percent)%")
                        .font(.headline.monospacedDigit()).foregroundStyle(DizzyPalette.accent)
                }
            }
            .padding(18)
            .background(DizzyPalette.surface, in: .rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("附言").font(.headline)
                    Spacer()
                    Text("\(model.comment.utf16.count)/\(offer.commentLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(model.comment.utf16.count > offer.commentLimit ? DizzyPalette.danger : DizzyPalette.mutedText)
                }
                TextField("想对创作者说的话（可选）", text: $model.comment, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(14)
                    .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("purchase.comment")
            }
            if let message = model.failure ?? validationMessage(offer) {
                Text(message).font(.footnote).foregroundStyle(DizzyPalette.accent)
            }
            Button {
                amountFocused = false
                Task { await model.prepare(summary: summary, account: account, purchases: purchases) }
            } label: {
                HStack {
                    if model.isPreparing { ProgressView() }
                    Text(model.isPreparing ? "正在准备…" : checkoutTitle(offer))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isPreparing || validationMessage(offer) != nil)
            .accessibilityIdentifier("purchase.checkout")
            Text("将打开 DizzyLab 收银台，使用支付宝完成付款。返回后会自动核验结果。")
                .font(.caption).foregroundStyle(DizzyPalette.mutedText)
        }
        .disabled(model.isPreparing)
    }

    private func validationMessage(_ offer: PurchaseOffer) -> String? {
        do { _ = try offer.validate(amountText: model.amountText, comment: model.comment); return nil }
        catch { return error.localizedDescription }
    }

    private func checkoutTitle(_ offer: PurchaseOffer) -> String {
        guard let amount = PurchaseAmount(text: model.amountText) else { return "使用支付宝付款" }
        return amount.cents == 0 ? "免费领取" : "支付宝付款 ¥\(amount.text)"
    }

    private func paymentStatus(_ pending: PendingPurchase) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if purchases.state == .checking {
                ProgressView("正在核验付款结果…")
            } else {
                Label(purchases.state == .confirmed ? "已确认到账" : "等待付款确认",
                      systemImage: purchases.state == .confirmed ? "checkmark.seal.fill" : "clock")
                    .font(.title3.bold())
                    .foregroundStyle(purchases.state == .confirmed ? DizzyPalette.success : DizzyPalette.accent)
            }
            Text("\(pending.title) · ¥\(pending.attempt.amount.text)")
                .font(.subheadline)
            if purchases.state == .confirmed {
                Text(pending.attempt.kind == .boost ? "感谢你对创作者的追加支持。" : "专辑已加入「已购买」，可以收听完整版和下载。")
                    .foregroundStyle(DizzyPalette.mutedText)
            } else {
                Text("如果已完成支付，到账可能稍有延迟。尚未确认前，请勿重复付款；稍后也可从「已购买」继续核验。")
                    .font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                if let failure = purchases.failure {
                    Text(failure).font(.footnote).foregroundStyle(DizzyPalette.accent)
                }
                if purchases.requiresLogin {
                    Button("重新登录") { showLogin = true }
                        .buttonStyle(.bordered)
                }
                Button("我已付款，重新核验") { Task { await purchases.check() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchases.state == .checking)
                Link("查看网站已付订单", destination: DizzyURL.page(pending.attempt.kind == .boost ? "/albums/purchases/boost/" : "/albums/purchases/"))
                Button("停止跟踪这笔付款", role: .destructive) { showStopConfirmation = true }
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CheckoutView: View {
    let session: CheckoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseStore.self) private var purchases
    @State private var isLoading = true
    @State private var failure: String?
    @State private var returnNotice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading { ProgressView().padding(8) }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(DizzyPalette.accent).padding()
                }
                if let returnNotice {
                    Text(returnNotice).font(.footnote).foregroundStyle(DizzyPalette.mutedText).padding()
                }
                CheckoutWebView(checkoutURL: session.url, credentials: session.credentials) { event in
                    switch event {
                    case .loadingChanged(let loading): isLoading = loading
                    case .siteReturned: dismiss()
                    case .openedAlipay: break
                    case .manualReturnNeeded:
                        returnNotice = "此收银台使用网页返回。支付完成后请回到 NeoDizzy，系统会继续核验到账。"
                    case .failed(let message): failure = message; isLoading = false
                    }
                }
                .id(session.id)
            }
            .dizzyPageBackground()
            .navigationTitle("支付宝收银台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("我已付款") { dismiss() } }
            }
            .onChange(of: purchases.state) { _, state in
                if state == .confirmed { dismiss() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in dismiss() }
        }
        .tint(DizzyPalette.accent)
        .preferredColorScheme(.dark)
    }
}
