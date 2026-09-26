// 移植自 MeloX（GPLv3）Core/Playback/Engine/AudioPlaybackSessionConfigurator.swift。

import AVFoundation

enum AudioSessionConfigurator {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try session.setCategory(.playback, mode: .default)
        }
        // 耳机断开时暂停，而不是改用扬声器外放。
        if !session.prefersInterruptionOnRouteDisconnect {
            try session.setPrefersInterruptionOnRouteDisconnect(true)
        }
        try session.setActive(true)
    }
}
