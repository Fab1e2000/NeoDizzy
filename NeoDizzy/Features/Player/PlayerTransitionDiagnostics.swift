import Foundation
import LNPopupUI
import QuartzCore
import UIKit

/// Opt-in diagnostic build only. Samples describe main-thread callback timing,
/// not GPU frame delivery. No playback metadata or user content is recorded.
@MainActor final class PlayerTransitionDiagnostics: NSObject {
    #if PLAYER_TRANSITION_DIAGNOSTICS
    private weak var host: NativePlayerContentController?
    private var displayLink: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var samples: [Sample] = []
    private var events: [Event] = []
    private var previousCallback: CFTimeInterval = 0

    nonisolated private struct Sample: Codable, Sendable {
        let elapsed: Double
        let callbackGap: Double
        let displayInterval: Double
        let frame: CGRect
        let hostedSize: CGSize
        let portal: Bool
        let gestureState: Int
    }
    nonisolated private struct Event: Codable, Sendable {
        let elapsed: Double
        let name: String
    }
    nonisolated private struct Capture: Codable, Sendable {
        let schema: Int
        let date: Date
        let events: [Event]
        let samples: [Sample]
    }

    func begin(_ name: String, host: NativePlayerContentController) {
        if displayLink == nil {
            self.host = host
            started = CACurrentMediaTime()
            previousCallback = 0
            samples = []
            samples.reserveCapacity(1800)
            events = []
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            // Do not request a different refresh rate for a diagnostic run.
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        mark(name)
    }

    func mark(_ name: String) {
        guard displayLink != nil, events.count < 100 else { return }
        events.append(Event(elapsed: CACurrentMediaTime() - started, name: name))
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let host, host.viewIfLoaded?.window != nil else {
            finish("host_unavailable")
            return
        }
        let now = CACurrentMediaTime()
        let portal = host.popupContentView.value(forKey: "transitionView") as? UIView
        let surface = portal ?? host.popupContentView
        let layer = surface.layer.presentation() ?? surface.layer
        samples.append(Sample(elapsed: now - started,
                              callbackGap: previousCallback == 0 ? 0 : now - previousCallback,
                              displayInterval: link.targetTimestamp - link.timestamp,
                              frame: layer.frame, hostedSize: host.hosting.view.bounds.size,
                              portal: portal != nil,
                              gestureState: host.popupContentView.popupInteractionGestureRecognizer.state.rawValue))
        previousCallback = now
        // Bounded even if a user holds the player or leaves the app mid-gesture.
        if samples.count >= 1800 || now - started >= 20 { finish("capture_limit") }
    }

    func finish(_ reason: String) {
        guard let link = displayLink else { return }
        mark(reason)
        link.invalidate()
        displayLink = nil
        host = nil
        let capture = Capture(schema: 1, date: Date(), events: events, samples: samples)
        samples = []
        events = []
        let directory = URL.documentsDirectory.appendingPathComponent("PlayerTransitionDiagnostics", isDirectory: true)
        Task.detached(priority: .utility) {
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let name = "transition-\(UUID().uuidString).json"
                try encoder.encode(capture).write(to: directory.appendingPathComponent(name), options: .atomic)
                let files = try manager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey])
                    .filter { $0.lastPathComponent.hasPrefix("transition-") && $0.pathExtension == "json" }
                    .sorted {
                        let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return lhs > rhs
                    }
                for file in files.dropFirst(30) { try? manager.removeItem(at: file) }
            } catch {
                NSLog("PlayerTransitionDiagnostics write failed: %@", String(describing: error))
            }
        }
    }
    #else
    func begin(_ name: String, host: NativePlayerContentController) {}
    func mark(_ name: String) {}
    func finish(_ reason: String) {}
    #endif
}
