import AVFoundation
import Accelerate
import Foundation

struct Clip: Identifiable, Equatable {
    let id = UUID()
    var number: Int
    var start: Double
    var end: Double
    var peaks: [Float]
    var isSelected = true
    var duration: Double { end - start }
}

@MainActor
@Observable
final class SplitterModel {
    var clips: [Clip] = []
    var fileName: String?
    var isLoading = false
    var failure: Failure?
    var settings = SplitSettings() { didSet { if settings != oldValue { resplit() } } }

    private(set) var buffer: AVAudioPCMBuffer?
    private var rms: [Float] = []
    private var peaks: [Float] = []
    private var peakCeiling: Float = 1
    private var duration = 0.0
    private var stem = "clip"

    var selectedCount: Int { clips.filter(\.isSelected).count }

    // MARK: - Caricamento

    func load(url: URL) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let analysis = try await Task.detached(priority: .userInitiated) {
                try Analysis(url: url)
            }.value
            buffer = analysis.buffer
            rms = analysis.rms
            peaks = analysis.peaks
            peakCeiling = max(analysis.peaks.max() ?? 1, 0.0001)
            bitDepth = analysis.bitDepth
            duration = analysis.duration
            stem = url.deletingPathExtension().lastPathComponent
            fileName = url.lastPathComponent
            resplit()
        } catch {
            buffer = nil
            clips = []
            fileName = nil
            failure = Failure(title: String(localized: "Impossibile aprire il file"),
                              message: (error as? SplitterError)?.text ?? error.localizedDescription)
        }
    }

    // MARK: - Taglio

    private func resplit() {
        guard buffer != nil else { return }
        let previous = clips
        clips = nonSilentRanges(rms: rms, hop: envelopeHop, duration: duration, settings: settings)
            .enumerated()
            .map { index, range in
                Clip(
                    number: index + 1,
                    start: range.start,
                    end: range.end,
                    peaks: waveform(from: range.start, to: range.end),
                    // Cambiando i cursori le clip si rigenerano: conserva la scelta
                    // di chi occupava lo stesso posto, non l'identità (che cambia).
                    isSelected: index < previous.count ? previous[index].isSelected : true
                )
            }
    }

    /// Barre della waveform, normalizzate sul picco dell'intero file così che
    /// una clip piano resti visibilmente più bassa di una forte.
    private func waveform(from start: Double, to end: Double, bars: Int = 110) -> [Float] {
        let first = Int(start / envelopeHop)
        let last = min(peaks.count, Int(end / envelopeHop))
        guard last > first else { return [] }
        let span = last - first
        return (0..<bars).map { bar in
            let lo = first + span * bar / bars
            let hi = max(lo + 1, first + span * (bar + 1) / bars)
            return (peaks[lo..<min(hi, last)].max() ?? 0) / peakCeiling
        }
    }

    // MARK: - Esportazione

    func slice(_ clip: Clip) -> AVAudioPCMBuffer? {
        guard let buffer, let source = buffer.floatChannelData else { return nil }
        let rate = buffer.format.sampleRate
        let from = max(0, Int(clip.start * rate))
        let to = min(Int(buffer.frameLength), Int(clip.end * rate))
        guard to > from,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(to - from)),
              let destination = out.floatChannelData
        else { return nil }
        out.frameLength = AVAudioFrameCount(to - from)
        for channel in 0..<Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel] + from, count: to - from)
        }
        return out
    }

    /// Scrive le clip selezionate come WAV nella cartella indicata.
    @discardableResult
    func export(to directory: URL) throws -> Int {
        guard let buffer else { return 0 }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        var written = 0
        for clip in clips where clip.isSelected {
            guard let slice = slice(clip) else { continue }
            let url = directory.appending(path: "\(stem) \(clip.number).wav")
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: slice)
            written += 1
        }
        return written
    }

    private var bitDepth = 24
}

/// Cosa mostrare nell'avviso: il titolo dice cosa non è riuscito, il messaggio perché.
struct Failure {
    var title: String
    var message: String
}

enum SplitterError: Error {
    case empty
    var text: String { String(localized: "Il file è vuoto o in un formato non supportato.") }
}

/// Lettura + inviluppo. Fuori dal main actor, gira in background.
// ponytail: carica tutto il file in RAM come float32 (~23 MB al minuto, stereo 48k).
// Va benissimo per librerie di effetti; se servono file da ore, leggere a blocchi.
/// `@unchecked`: il buffer viene consegnato al modello, non condiviso.
struct Analysis: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let rms: [Float]
    let peaks: [Float]
    let duration: Double
    let bitDepth: Int

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { throw SplitterError.empty }
        try file.read(into: buffer)

        let frames = Int(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { throw SplitterError.empty }

        let window = max(1, Int(format.sampleRate * envelopeHop))
        var rms: [Float] = []
        var peaks: [Float] = []
        rms.reserveCapacity(frames / window + 1)
        peaks.reserveCapacity(frames / window + 1)

        var offset = 0
        while offset < frames {
            let count = vDSP_Length(min(window, frames - offset))
            var loudest: Float = 0
            var highest: Float = 0
            // Il canale più forte decide: una clip presente su un solo canale non va persa.
            for channel in 0..<Int(format.channelCount) {
                var value: Float = 0
                vDSP_rmsqv(channels[channel] + offset, 1, &value, count)
                loudest = max(loudest, value)
                vDSP_maxmgv(channels[channel] + offset, 1, &value, count)
                highest = max(highest, value)
            }
            rms.append(loudest)
            peaks.append(highest)
            offset += window
        }

        self.buffer = buffer
        self.rms = rms
        self.peaks = peaks
        self.duration = Double(frames) / format.sampleRate
        // Se la sorgente è PCM conserviamo la sua risoluzione, altrimenti 24 bit.
        self.bitDepth = file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 24
    }
}
