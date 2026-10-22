import SwiftUI

/// 加载失败：说明与重试。
struct LoadFailureView: View {
    let message: String
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
            Button("重试") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DizzyPalette.accentFill)
            .foregroundStyle(DizzyPalette.onAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

/// Content placeholders are immediate and static; progress indicators are reserved for operations.
enum ContentSkeletonLayout {
    case grid, rows, songs, numberedSongs, comments, article, lyrics, profile, pack
}

struct ContentSkeleton: View {
    var layout: ContentSkeletonLayout = .grid
    var count = 4

    var body: some View {
        Group {
            switch layout {
            case .grid:
                LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                    ForEach(0..<count, id: \.self) { _ in card }
                }
            case .rows:
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<count, id: \.self) { _ in row }
                }
            case .songs, .numberedSongs:
                VStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { _ in SongRowPlaceholder(numbered: layout == .numberedSongs) }
                }
            case .comments:
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<count, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            row
                            lines
                        }
                    }
                }
            case .article:
                VStack(alignment: .leading, spacing: 20) {
                    Text("文章标题与内容").font(.title2.bold()).redacted(reason: .placeholder)
                    row
                    ForEach(0..<count, id: \.self) { _ in lines }
                }
            case .lyrics:
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(0..<count, id: \.self) { _ in
                        Text("等待音乐里的故事").font(.system(size: 36, weight: .bold))
                            .redacted(reason: .placeholder)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .profile:
                VStack(alignment: .leading, spacing: 24) {
                    row
                    lines
                    ContentSkeleton(layout: .grid)
                }
            case .pack:
                VStack(spacing: 24) {
                    card.frame(maxWidth: 260)
                    RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.18)).frame(height: 44)
                    ContentSkeleton(layout: .grid)
                }.frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载内容")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.18)).aspectRatio(1, contentMode: .fit)
            Text("音乐与故事\n等待与你相遇").font(.subheadline.weight(.semibold))
                .lineLimit(2).redacted(reason: .placeholder)
            Text("创作者与作品信息").font(.caption).redacted(reason: .placeholder)
        }
    }
    private var row: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.18)).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text("名称与标题").font(.headline)
                Text("内容简介与相关信息").font(.caption)
            }.redacted(reason: .placeholder)
            Spacer(minLength: 0)
        }
    }
    private var lines: some View {
        Text("这里是尚未载入的内容占位。\n页面内容将在加载完成后显示。\n保留文字内容的排版空间。")
            .font(.body).lineSpacing(6).redacted(reason: .placeholder)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 移植自 MeloX（GPLv3）Shared/Components/MusicCollectionPaginationFooter.swift：加载前先稍等片刻。
/// 列表底部：出现在屏幕上时自动加载下一页，失败时显示重试。
/// 必须放在 Lazy 容器里，否则一创建就会触发加载。
struct PaginationFooter<Item: Identifiable & Sendable>: View {
    let list: PagedList<Item>
    var skeleton: ContentSkeletonLayout = .grid

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
                ContentSkeleton(layout: skeleton, count: 2)
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

/// 自己管分页的列表（网易云、用户主页）共用的底栏：出现在屏幕上时自动加载下一页，不用点按钮。
/// `progress` 每加载一页就会变（例如已加载条数），变了之后底栏仍在屏幕上就继续加载。必须放在 Lazy 容器里。
struct AutoLoadMoreFooter<Placeholder: View>: View {
    let progress: Int
    let load: () async -> Void
    @ViewBuilder var placeholder: Placeholder

    var body: some View {
        placeholder
            .task(id: progress) {
                // 与 PaginationFooter 相同：先等一会儿，滚出屏幕的底栏会在发请求前被取消。
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await load()
            }
    }
}

/// 分页列表的外壳：首次加载、失败、空列表，内容之后接分页底栏。
struct PagedContent<Item: Identifiable & Sendable, Content: View>: View {
    let list: PagedList<Item>
    var skeleton: ContentSkeletonLayout = .grid
    var emptyMessage: LocalizedStringKey = "这里还没有内容。"
    @ViewBuilder let content: ([Item]) -> Content

    var body: some View {
        if list.items.isEmpty {
            if let failure = list.failure {
                LoadFailureView(message: failure) { await list.reload() }
            } else if list.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else {
                ContentSkeleton(layout: skeleton)
                    .task { await list.loadMore() }
            }
        } else {
            content(list.items)
            if list.hasMore || list.failure != nil {
                PaginationFooter(list: list, skeleton: skeleton)
            }
        }
    }
}

/// 只加载一次的页面（专辑、社团、pack）的外壳。加载中和失败时也铺满整页，
/// 页面底色才能盖住整个屏幕，转场时不会露出一块矩形。
struct LoadableContent<Value, Content: View>: View {
    let state: Loadable<Value>
    var skeleton: ContentSkeletonLayout = .grid
    var skeletonIsPage = false
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if let value = state.value {
                content(value)
            } else if let failure = state.failure {
                LoadFailureView(message: failure) { await state.load() }
            } else {
                if skeletonIsPage {
                    ScrollView { ContentSkeleton(layout: skeleton).padding(20) }
                } else {
                    ContentSkeleton(layout: skeleton)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await state.loadIfNeeded() }
    }
}
