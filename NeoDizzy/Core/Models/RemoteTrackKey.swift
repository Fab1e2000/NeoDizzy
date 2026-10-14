import Foundation

/// 在线曲目的来源标识，用于关联本地文件，不改变播放队列中的 Track.id。
nonisolated struct RemoteTrackKey: Hashable, Codable, Sendable {
    let provider: String
    let itemID: String
}

extension Track {
    var remoteKey: RemoteTrackKey? {
        if let remoteSource {
            return RemoteTrackKey(provider: remoteSource.providerID, itemID: remoteSource.itemID)
        }
        guard localSource == nil, !discID.isEmpty else { return nil }
        return RemoteTrackKey(provider: "dizzylab", itemID: "\(discID)/\(number)")
    }
}
