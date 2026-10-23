// 移植自 MeloX（GPLv3）Core/Playback/Engine/AudioPlaybackSessionConfigurator.swift。

import AVFoundation

enum AudioSessionConfigurator {
    static func activate(completion: @escaping AudioSessionActivationCoordinator.Completion) {
        do {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.mode != .default || !session.categoryOptions.isEmpty {
            try session.setCategory(.playback, mode: .default)
        }
        // 耳机断开时暂停，而不是改用扬声器外放。
        if !session.prefersInterruptionOnRouteDisconnect {
            try session.setPrefersInterruptionOnRouteDisconnect(true)
        }
        session.activate(options: []) { activated, error in
            Task { @MainActor in
                if let error { completion(.failure(error)) }
                else if activated { completion(.success(())) }
                else { completion(.failure(NSError(domain: "AudioSession", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "音频会话未能激活"]))) }
            }
        }
        } catch { completion(.failure(error)) }
    }
}
