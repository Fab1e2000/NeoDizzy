import SwiftUI
import UIKit

nonisolated struct UpcomingQueueEntry: Identifiable, Hashable, Sendable {
    struct ID: Hashable {
        let songID: String
        let occurrence: Int
    }

    let id: ID
    let queueIndex: Int
    let song: Track
}

/// 继续播放列表。用原生 `UICollectionView` 的交互式移动做拖动排序：
/// 被拖行只能上下移动，拖起时整行（通栏）换成半透明高亮底色，和系统音乐一致。
/// 行内容仍由 SwiftUI 渲染。SwiftUI 的 `List` 走的是拖放，没有这两项的公开接口。
struct NowPlayingQueueList: UIViewRepresentable {
    @Environment(\.nowPlayingBackdropImage) private var backdropImage
    @Environment(\.nowPlayingBackdropFrame) private var backdropFrame
    let entries: [UpcomingQueueEntry]
    var subtitle: String = "接下来播放的歌曲"
    /// 顶部给歌曲头部和模式按钮预留的高度，头部叠在上层，随列表滚动。
    let headerHeight: CGFloat
    /// 行内容离屏幕两侧的距离；列表本身通栏，高亮才能铺满宽度。
    let horizontalInset: CGFloat
    let onPlay: (Int) -> Void
    let onMove: (IndexSet, Int) -> Void
    /// 滚动偏移，限制在 `0...headerHeight`。
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> OverflowContainer {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        // 收起手势由播放器的显式区域接收，列表区域始终只处理滚动和排序。
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.allowsSelection = false
        collectionView.showsVerticalScrollIndicator = true
        collectionView.overrideUserInterfaceStyle = .dark
        collectionView.delegate = context.coordinator
        context.coordinator.attach(to: collectionView, initial: self)
        return OverflowContainer(collectionView: collectionView, overflow: horizontalInset)
    }

    func updateUIView(_ container: OverflowContainer, context: Context) {
        container.overflow = horizontalInset
        context.coordinator.update(with: self)
    }

    /// 布局上只占页面的宽度，列表本身向左右各多出 `overflow`，高亮才能通栏。
    final class OverflowContainer: UIView {
        let collectionView: UICollectionView
        var overflow: CGFloat {
            didSet { setNeedsLayout() }
        }

        init(collectionView: UICollectionView, overflow: CGFloat) {
            self.collectionView = collectionView
            self.overflow = overflow
            super.init(frame: .zero)
            clipsToBounds = false
            addSubview(collectionView)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            collectionView.frame = bounds.insetBy(dx: -overflow, dy: 0)
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            collectionView.frame.contains(point)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        private nonisolated enum Section: Sendable { case header, queue }
        private nonisolated enum Item: Hashable, Sendable {
            case spacer
            case title
            case empty
            case track(UpcomingQueueEntry.ID)
        }

        private var latest: NowPlayingQueueList?
        private var entriesByID: [UpcomingQueueEntry.ID: UpcomingQueueEntry] = [:]
        private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
        private var hasApplied = false
        /// 手指按在拖动手柄上的那一行；系统的交互式移动没有公开的"正在拖动"状态，这里自己记。
        private var pressedItem: Item?

        func attach(to collectionView: UICollectionView, initial: NowPlayingQueueList) {
            latest = initial
            let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
                [weak self] cell, _, item in
                self?.configure(cell, item: item)
            }
            let dataSource = UICollectionViewDiffableDataSource<Section, Item>(
                collectionView: collectionView
            ) { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: item
                )
            }
            dataSource.reorderingHandlers.canReorderItem = { item in
                if case .track = item { true } else { false }
            }
            dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
                self?.didReorder(transaction)
            }
            self.dataSource = dataSource

            let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delegate = self
            collectionView.addGestureRecognizer(press)

            update(with: initial)
        }

        func update(with list: NowPlayingQueueList) {
            guard let dataSource else { return }
            let previous = entriesByID
            let previousList = latest
            latest = list
            entriesByID = Dictionary(
                list.entries.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.header, .queue])
            snapshot.appendItems([.spacer, .title], toSection: .header)
            snapshot.appendItems(
                list.entries.isEmpty ? [.empty] : list.entries.map { .track($0.id) },
                toSection: .queue
            )

            // 同一行换了曲目信息（元数据更新）时重新配置；位置变化不需要，点播时现查下标。
            var reconfigured: [Item] = list.entries.compactMap { entry in
                previous[entry.id].map { $0.song != entry.song } == true ? .track(entry.id) : nil
            }
            if let previousList,
               previousList.subtitle != list.subtitle
                || previousList.headerHeight != list.headerHeight
                || previousList.horizontalInset != list.horizontalInset
                || previousList.backdropImage !== list.backdropImage
                || previousList.backdropFrame != list.backdropFrame {
                reconfigured += [.spacer, .title, .empty] + list.entries.map { .track($0.id) }
            }
            let existing = Set(snapshot.itemIdentifiers)
            snapshot.reconfigureItems(reconfigured.filter(existing.contains))

            dataSource.apply(snapshot, animatingDifferences: hasApplied)
            hasApplied = true
        }

        private func configure(_ cell: UICollectionViewListCell, item: Item) {
            guard let latest else { return }
            let inset = latest.horizontalInset

            cell.accessories = []
            // 拖动手柄默认贴着列表边缘，列表通栏所以要往里收，和行内容对齐。
            // 真机实测：手柄右缘 = 列表宽度 - 此边距 + 1.5，+1.5 让右缘正好落在内容边上。
            cell.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 0, leading: 0, bottom: 0, trailing: inset + 1.5
            )
            cell.configurationUpdateHandler = { [weak self] cell, state in
                var background = UIBackgroundConfiguration.clear()
                if self?.pressedItem == item || state.cellDragState != .none {
                    background.backgroundColor = UIColor.white.withAlphaComponent(0.2)
                    background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
                }
                cell.backgroundConfiguration = background
            }

            switch item {
            case .spacer:
                let height = latest.headerHeight + 44
                cell.contentConfiguration = UIHostingConfiguration {
                    Color.clear.frame(height: height)
                }
                .margins(.all, 0)
                .minSize(height: 0)

            case .title:
                cell.contentConfiguration = UIHostingConfiguration {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("继续播放")
                            .font(.headline.bold())
                            .foregroundStyle(Color.white)
                        NowPlayingVibrantLabel(text: latest.subtitle, fontSize: 13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.nowPlayingBackdropImage, latest.backdropImage)
                    .environment(\.nowPlayingBackdropFrame, latest.backdropFrame)
                }
                .margins(.horizontal, inset)
                .margins(.top, 14)
                .margins(.bottom, 12)
                .minSize(height: 0)

            case .empty:
                cell.contentConfiguration = UIHostingConfiguration {
                    ContentUnavailableView(
                        "后面没有要播放的曲目了",
                        systemImage: "list.bullet"
                    )
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .margins(.horizontal, inset)
                .margins(.vertical, 24)
                .minSize(height: 0)

            case .track(let id):
                guard let entry = entriesByID[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    NowPlayingQueueRow(entry: entry) { [weak self] in
                        guard let self, let index = self.entriesByID[id]?.queueIndex else { return }
                        self.latest?.onPlay(index)
                    }
                    .environment(\.nowPlayingBackdropImage, latest.backdropImage)
                    .environment(\.nowPlayingBackdropFrame, latest.backdropFrame)
                }
                .margins(.leading, inset)
                .margins(.trailing, 0)
                .margins(.vertical, 4)
                .minSize(height: 0)
                cell.accessories = [
                    .reorder(
                        displayed: .always,
                        options: .init(tintColor: UIColor.white.withAlphaComponent(0.45))
                    )
                ]
            }
        }

        private func didReorder(
            _ transaction: NSDiffableDataSourceTransaction<Section, Item>
        ) {
            let initial = transaction.initialSnapshot.itemIdentifiers(inSection: .queue)
            let final = transaction.finalSnapshot.itemIdentifiers(inSection: .queue)
            for change in final.difference(from: initial).inferringMoves() {
                guard case let .remove(source, _, associatedWith?) = change else { continue }
                latest?.onMove(IndexSet(integer: source), associatedWith > source ? associatedWith + 1 : associatedWith)
                return
            }
        }

        // MARK: Drag handle press

        private func handleRegion(in collectionView: UICollectionView) -> CGFloat {
            collectionView.bounds.width - (latest?.horizontalInset ?? 0) - 64
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let collectionView = gestureRecognizer.view as? UICollectionView else { return false }
            let location = gestureRecognizer.location(in: collectionView)
            guard location.x > handleRegion(in: collectionView),
                  let indexPath = collectionView.indexPathForItem(at: location),
                  case .track = dataSource?.itemIdentifier(for: indexPath)
            else { return false }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView = recognizer.view as? UICollectionView, let dataSource else { return }
            switch recognizer.state {
            case .began:
                let location = recognizer.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
                setPressedItem(dataSource.itemIdentifier(for: indexPath), in: collectionView)
            case .ended, .cancelled, .failed:
                setPressedItem(nil, in: collectionView)
            default:
                break
            }
        }

        private func setPressedItem(_ item: Item?, in collectionView: UICollectionView) {
            let previous = pressedItem
            pressedItem = item
            for changed in [previous, item].compactMap({ $0 }) {
                if let indexPath = dataSource?.indexPath(for: changed) {
                    collectionView.cellForItem(at: indexPath)?.setNeedsUpdateConfiguration()
                }
            }
        }

        // MARK: UICollectionViewDelegate

        func collectionView(
            _ collectionView: UICollectionView,
            targetIndexPathForMoveOfItemAt originalIndexPath: IndexPath,
            toProposedIndexPath proposedIndexPath: IndexPath
        ) -> IndexPath {
            clampedMoveTarget(from: originalIndexPath, to: proposedIndexPath)
        }

        /// 旧名字的同一个回调，系统用哪个都按同样的规则限制。
        func collectionView(
            _ collectionView: UICollectionView,
            targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
            toProposedIndexPath proposedIndexPath: IndexPath
        ) -> IndexPath {
            clampedMoveTarget(from: originalIndexPath, to: proposedIndexPath)
        }

        /// 只能在"继续播放"的曲目之间移动，不能落到顶部占位或标题的位置。
        private func clampedMoveTarget(from original: IndexPath, to proposed: IndexPath) -> IndexPath {
            guard proposed.section == original.section else {
                return IndexPath(item: proposed.section < original.section ? 0 : max(original.item, 0), section: original.section)
            }
            return proposed
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let latest else { return }
            // 保持现有顶部边界，头部滚动与吸附不额外叠加橡皮筋位移。
            let top = -scrollView.adjustedContentInset.top
            if scrollView.contentOffset.y < top {
                scrollView.contentOffset.y = top
            }
            let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            latest.onScroll(min(max(offset, 0), latest.headerHeight))
            // 手指按着往下拉列表时不振。
            if let previous = previousOffset, latest.headerHeight > 0,
               !(scrollView.isTracking && offset < previous) {
                playSnapFeedbackIfReached(from: previous, to: offset, headerHeight: latest.headerHeight)
            }
            previousOffset = offset
        }

        private var previousOffset: CGFloat?
        private let snapFeedback = UIImpactFeedbackGenerator(style: .soft)

        /// 滚到两个停靠位置之一（头部完整露出、头部刚好滚出去）就振一下，
        /// 吸附、惯性经过、手指往上推过去都算；离开后再回来才会再振。
        private func playSnapFeedbackIfReached(from previous: CGFloat, to offset: CGFloat, headerHeight: CGFloat) {
            for anchor in [0, headerHeight] {
                let wasAway = abs(previous - anchor) >= 0.5
                let reached = (previous - anchor) * (offset - anchor) <= 0
                if wasAway && reached {
                    snapFeedback.impactOccurred(intensity: 1)
                    snapFeedback.prepare()
                    return
                }
            }
        }

        /// 松手后不停在歌曲头部只露出一部分的位置：要么头部完整露出，要么整个滚出去（模式按钮贴顶）。
        /// 有明显滑动方向时顺着方向吸附，否则吸到较近的一端。
        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard let headerHeight = latest?.headerHeight, headerHeight > 0 else { return }
            let top = -scrollView.adjustedContentInset.top
            let target = targetContentOffset.pointee.y - top
            guard target > 0, target < headerHeight else { return }
            // 列表太短、滚不到头部完全隐藏的位置时，只能回到顶部。
            let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height - top
            let canHideHeader = maxOffset >= headerHeight
            let hidesHeader: Bool
            if velocity.y > 0.2 {
                hidesHeader = true
            } else if velocity.y < -0.2 {
                hidesHeader = false
            } else {
                hidesHeader = target >= headerHeight / 2
            }
            targetContentOffset.pointee.y = top + (hidesHeader && canHideHeader ? headerHeight : 0)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            snapFeedback.prepare()
        }
    }
}
