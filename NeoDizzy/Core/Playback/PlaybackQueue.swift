// 移植自 MeloX（GPLv3）Core/Playback/Queue/PlaybackQueue.swift：
// 曲目类型换成 Track，去掉用不到的插播和拖动排序。

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
        let order = isShuffled ? shuffledOrder : Array(tracks.indices)
        guard !order.isEmpty else { return false }
        let position = isShuffled ? shuffledPosition : currentIndex
        var destination = position + offset
        if order.indices.contains(destination) {
            // 按现有顺序继续。
        } else if wraps {
            destination = offset > 0 ? 0 : order.count - 1
        } else {
            return false
        }

        if isShuffled {
            shuffledPosition = destination
            currentIndex = order[destination]
        } else {
            currentIndex = destination
        }
        return true
    }

    func canMove(by offset: Int, wraps: Bool) -> Bool {
        let order = isShuffled ? shuffledOrder : Array(tracks.indices)
        guard !order.isEmpty else { return false }
        let position = isShuffled ? shuffledPosition : currentIndex
        return order.indices.contains(position + offset) || wraps
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
}
