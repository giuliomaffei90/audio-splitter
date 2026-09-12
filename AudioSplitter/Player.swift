import AVFoundation
import Foundation

/// Riproduce una clip alla volta dal buffer già in memoria.
@MainActor
@Observable
final class Player {
    private(set) var playingID: Clip.ID?
    private(set) var progress = 0.0

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var ticker: Timer?
    private var startedAt = Date()
    private var length = 0.0

    func toggle(_ clip: Clip, from model: SplitterModel) {
        if playingID == clip.id { stop(); return }
        stop()
        guard let slice = model.slice(clip) else { return }

        if node.engine == nil {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: slice.format)
        }
        guard (try? engine.start()) != nil else { return }

        node.scheduleBuffer(slice, completionHandler: nil)
        node.play()

        playingID = clip.id
        length = clip.duration
        startedAt = Date()
        progress = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        node.stop()
        playingID = nil
        progress = 0
    }

    private func tick() {
        progress = min(1, Date().timeIntervalSince(startedAt) / max(length, 0.001))
        if progress >= 1 { stop() }
    }
}
