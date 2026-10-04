import SwiftUI

/// 加载失败：说明、重试，以及「在网页中打开」的退路（网站改版导致解析失败时仍能看到内容）。
struct FailureView: View {
    let message: String
    var webURL: URL?
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("无法加载", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("重试") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
                if let webURL {
                    Link("在网页中打开", destination: webURL)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 首次加载时的转圈。稍等片刻才出现，加载很快时不会闪一下。
struct DelayedProgress: View {
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeIn(duration: 0.2)) { isVisible = true }
            }
    }
}

/// 列表底部：滚动到这里时加载下一页，失败时显示重试。必须放在 Lazy 容器里。
struct PaginationLoader<Item: Identifiable & Sendable>: View {
    let list: PagedList<Item>

    var body: some View {
        Group {
            if let failure = list.failure {
                VStack(spacing: 8) {
                    Text(failure).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("重新加载") { Task { await list.loadMore() } }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .task(id: list.loadedPages) {
                        // 等一会儿再请求：滚出视野的底栏会被取消，内容不满一屏时继续翻页。
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await list.loadMore()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// 分页内容的外壳：首次加载、失败、空列表，内容之后接分页底栏。
struct PagedSection<Item: Identifiable & Sendable, Content: View>: View {
    let list: PagedList<Item>
    var webURL: URL?
    var emptyTitle: LocalizedStringKey = "这里还没有内容"
    var emptySystemImage = "tray"
    @ViewBuilder let content: ([Item]) -> Content

    var body: some View {
        if list.items.isEmpty {
            if let failure = list.failure {
                FailureView(message: failure, webURL: webURL) { await list.reload() }
            } else if list.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
                    .padding(.vertical, 40)
            } else {
                DelayedProgress()
                    .task { await list.loadMore() }
            }
        } else {
            content(list.items)
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
            if list.hasMore || list.failure != nil {
                PaginationLoader(list: list)
            }
        }
    }
}

/// 只加载一次的页面（专辑、社团、pack）的外壳，加载中和失败时铺满内容区。
struct LoadablePage<Value, Content: View>: View {
    let state: Loadable<Value>
    var webURL: URL?
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if let value = state.value {
                content(value)
                    .transition(.opacity)
            } else if let failure = state.failure {
                FailureView(message: failure, webURL: webURL) { await state.load() }
            } else {
                DelayedProgress()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 内容加载完成时淡入，而不是突然替换掉转圈。
        .animation(.easeOut(duration: 0.2), value: state.value == nil)
        .task { await state.loadIfNeeded() }
    }
}

/// 需要登录的页面在未登录或登录失效时的提示。
struct LoginPromptView: View {
    @Environment(AccountStore.self) private var account
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(account.isSessionExpired ? "登录已失效" : "登录 DizzyLab", systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button(account.isSessionExpired ? "重新登录" : "登录") { account.isLoginPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
