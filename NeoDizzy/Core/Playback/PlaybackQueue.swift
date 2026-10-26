// 移植自 MeloX（GPLv3）Core/Playback/Queue/PlaybackQueue.swift：
// 曲目类型换成 Track，保留播放顺序及待播放队列拖动排序，省略插播。

import Foundation

nonisolated enum RepeatMode: String, CaseIterable, Codable, Sendable {
    case off
    case all
    case one

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .off: String(localized: "不循环")
        case .all: String(localized: "列表循环")
        case .one: String(localized: "单曲循环")
        }
    }

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

nonisolated struct PlaybackQueue: Sendable {
    private(set) var tracks: [Track] = []
    private(set) var currentIndex = 0
    private(set) var isShuffled = false

    private var shuffledOrder: [Int] = []
    private var shuffledPosition = 0

    var currentTrack: Track? {
        guard tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    var persistedShuffleOrder: [Int] {
        shuffledOrder
    }

    /// 当前曲目在播放顺序里的位置，随机播放时按随机顺序计。
    var position: Int {
        isShuffled ? shuffledPosition : currentIndex
    }

    /// 接下来要播放的曲目下标，按播放顺序（随机时按随机顺序）。列表循环时接上开头的曲目。
    func upcomingIndices(wraps: Bool) -> [Int] {
        guard !tracks.isEmpty else { return [] }
        let order = isShuffled ? shuffledOrder : Array(tracks.indices)
        let position = isShuffled ? shuffledPosition : currentIndex
        let nextPosition = min(position + 1, order.count)
        let remaining = Array(order.dropFirst(nextPosition))
        guard wraps, position > 0 else { return remaining }
        return remaining + Array(order.prefix(position))
    }

    /// 播放顺序里的上一首下标（随机时按随机顺序）。列表循环时第一首接最后一首。
    func previousIndex(wraps: Bool) -> Int? {
        guard !tracks.isEmpty else { return nil }
        if position > 0 { return index(at: position - 1) }
        return wraps && tracks.count > 1 ? index(at: tracks.count - 1) : nil
    }

    /// 只取相邻条目时不构造整份待播队列。与 upcomingIndices 一样，不把当前条目作为下一首。
    func nextIndex(wraps: Bool) -> Int? {
        guard tracks.count > 1 else { return nil }
        if position + 1 < tracks.count { return index(at: position + 1) }
        return wraps ? index(at: 0) : nil
    }

    private func index(at position: Int) -> Int {
        isShuffled ? shuffledOrder[position] : position
    }

    mutating func updateMetadata(_ replacements: [String: Track]) {
        tracks = tracks.map { replacements[$0.id] ?? $0 }
    }

    /// 跳到队列里的某一首。随机播放时保持随机顺序，只移动当前位置。
    mutating func select(index: Int) -> Bool {
        guard tracks.indices.contains(index) else { return false }
        currentIndex = index
        alignShufflePosition()
        return true
    }

    mutating func restore(tracks: [Track], currentIndex: Int, isShuffled: Bool, shuffledOrder: [Int]) {
        self.tracks = tracks
        self.currentIndex = tracks.isEmpty ? 0 : min(max(currentIndex, 0), tracks.count - 1)
        self.isShuffled = isShuffled

        if isShuffled, isValidShuffleOrder(shuffledOrder) {
            self.shuffledOrder = shuffledOrder
            shuffledPosition = shuffledOrder.firstIndex(of: self.currentIndex) ?? 0
        } else if isShuffled {
            rebuildShuffleOrder()
        } else {
            self.shuffledOrder = []
            shuffledPosition = 0
        }
    }

    mutating func replace(with tracks: [Track], startingAt index: Int) {
        self.tracks = tracks
        currentIndex = tracks.isEmpty ? 0 : min(max(index, 0), tracks.count - 1)
        if isShuffled {
            rebuildShuffleOrder()
        }
    }

    mutating func move(by offset: Int, wraps: Bool) -> Bool {
        guard !tracks.isEmpty else { return false }
        var destination = position + offset
        if tracks.indices.contains(destination) {
            // 按现有顺序继续。
        } else if wraps {
            destination = offset > 0 ? 0 : tracks.count - 1
        } else {
            return false
        }

        if isShuffled {
            shuffledPosition = destination
            currentIndex = shuffledOrder[destination]
        } else {
            currentIndex = destination
        }
        return true
    }

    func canMove(by offset: Int, wraps: Bool) -> Bool {
        guard !tracks.isEmpty else { return false }
        return tracks.indices.contains(position + offset) || wraps
    }

    mutating func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            rebuildShuffleOrder()
        } else {
            shuffledOrder = []
            shuffledPosition = 0
        }
    }

    /// 当前曲目排在随机顺序的第一位，其余打乱。
    mutating func moveUpcomingSongs(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        wraps: Bool
    ) {
        if isShuffled {
            var positions = Array(
                shuffledOrder.indices.dropFirst(
                    min(shuffledPosition + 1, shuffledOrder.count)
                )
            )
            if wraps, shuffledPosition > 0 {
                positions.append(
                    contentsOf: shuffledOrder.indices.prefix(
                        shuffledPosition
                    )
                )
            }
            let upcomingOrder = moved(
                positions.map { shuffledOrder[$0] },
                fromOffsets: source,
                toOffset: destination
            )
            for (position, songIndex) in zip(
                positions,
                upcomingOrder
            ) {
                shuffledOrder[position] = songIndex
            }
            return
        }

        var positions = Array(
            tracks.indices.dropFirst(
                min(currentIndex + 1, tracks.count)
            )
        )
        if wraps, currentIndex > 0 {
            positions.append(
                contentsOf: tracks.indices.prefix(currentIndex)
            )
        }
        let upcomingSongs = moved(
            positions.map { tracks[$0] },
            fromOffsets: source,
            toOffset: destination
        )
        for (position, song) in zip(positions, upcomingSongs) {
            tracks[position] = song
        }
    }

    private mutating func rebuildShuffleOrder() {
        guard tracks.indices.contains(currentIndex) else {
            shuffledOrder = []
            shuffledPosition = 0
            return
        }
        shuffledOrder = [currentIndex] + tracks.indices.filter { $0 != currentIndex }.shuffled()
        shuffledPosition = 0
    }

    private mutating func alignShufflePosition() {
        guard isShuffled else { return }
        if let position = shuffledOrder.firstIndex(of: currentIndex) {
            shuffledPosition = position
        } else {
            rebuildShuffleOrder()
        }
    }

    private func isValidShuffleOrder(_ order: [Int]) -> Bool {
        order.count == tracks.count && Set(order) == Set(tracks.indices)
    }
    private func moved<Element>(
        _ elements: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Element] {
        let validSource = source
            .filter(elements.indices.contains)
            .sorted()
        guard !validSource.isEmpty else { return elements }

        var result = elements
        let movingElements = validSource.map { elements[$0] }
        for index in validSource.reversed() {
            result.remove(at: index)
        }

        let removedBeforeDestination = validSource.filter {
            $0 < destination
        }.count
        let insertionIndex = min(
            max(destination - removedBeforeDestination, 0),
            result.count
        )
        result.insert(contentsOf: movingElements, at: insertionIndex)
        return result
    }
}
