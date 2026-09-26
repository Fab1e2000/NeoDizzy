import SwiftUI

/// 加载失败：说明、重试，以及「在网页中打开」的退路（网站改版导致解析失败时仍能看到内容）。
struct LoadFailureView: View {
    let message: String
    var webURL: URL?
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(DizzyPalette.mutedText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("重试") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
                if let webURL {
                    Link("在网页中打开", destination: webURL)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

/// 首次加载时的转圈。稍等片刻才出现，加载很快时（例如推入页面的转场中）不会闪一下。
struct LoadingView: View {
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
            .task {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeIn(duration: 0.2)) { isVisible = true }
            }
    }
}

// 移植自 MeloX（GPLv3）Shared/Components/MusicCollectionPaginationFooter.swift：加载前先稍等片刻。
/// 列表底部：出现在屏幕上时自动加载下一页，失败时显示重试。
/// 必须放在 Lazy 容器里，否则一创建就会触发加载。
struct PaginationFooter<Item: Identifiable & Sendable>: View {
    let list: PagedList<Item>

    var body: some View {
        Group {
            if let failure = list.failure {
                VStack(spacing: 8) {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        Task { await list.loadMore() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView()
                    .task(id: list.loadedPages) {
                        // 页码变化后继续触发，整页都是重复条目时也能翻到下一页。
                        // 先等一会儿：离开屏幕的底栏会在发请求前被取消，内容不满一屏时再接着加载。
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await list.loadMore()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// 分页列表的外壳：首次加载、失败、空列表，内容之后接分页底栏。
struct PagedContent<Item: Identifiable & Sendable, Content: View>: View {
    let list: PagedList<Item>
    var webURL: URL?
    var emptyMessage: LocalizedStringKey = "这里还没有内容。"
    @ViewBuilder let content: ([Item]) -> Content

    var body: some View {
        if list.items.isEmpty {
            if let failure = list.failure {
                LoadFailureView(message: failure, webURL: webURL) { await list.reload() }
            } else if list.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else {
                LoadingView()
                    .task { await list.loadMore() }
            }
        } else {
            content(list.items)
            if list.hasMore || list.failure != nil {
                PaginationFooter(list: list)
            }
        }
    }
}

/// 只加载一次的页面（专辑、社团、pack）的外壳。加载中和失败时也铺满整页，
/// 页面底色才能盖住整个屏幕，转场时不会露出一块矩形。
struct LoadableContent<Value, Content: View>: View {
    let state: Loadable<Value>
    var webURL: URL?
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if let value = state.value {
                content(value)
            } else if let failure = state.failure {
                LoadFailureView(message: failure, webURL: webURL) { await state.load() }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await state.loadIfNeeded() }
    }
}
