import Foundation

/// Parametri di taglio. Sono i knob da tarare: materiale diverso, silenzi diversi.
struct SplitSettings: Equatable {
    var thresholdDB: Double = -40
    var minSilence: Double = 0.5
    var padding: Double = 0.1
    var minClip: Double = 0.15
}

/// Passo dell'inviluppo, in secondi. Risoluzione dell'analisi.
let envelopeHop = 0.01

/// Trova gli intervalli non silenziosi a partire da un inviluppo RMS a passo costante.
/// Logica pura, senza AVFoundation, così è verificabile da sola (vedi check/main.swift).
func nonSilentRanges(
    rms: [Float],
    hop: Double,
    duration: Double,
    settings s: SplitSettings
) -> [(start: Double, end: Double)] {
    guard !rms.isEmpty, duration > 0 else { return [] }

    let threshold = Float(pow(10.0, s.thresholdDB / 20.0))
    let minSilenceWindows = max(1, Int((s.minSilence / hop).rounded(.up)))

    // 1. Raccogli i silenzi abbastanza lunghi.
    var silences: [(start: Double, end: Double)] = []
    var runStart: Int? = nil
    for i in 0...rms.count {
        let quiet = i < rms.count && rms[i] <= threshold
        if quiet {
            if runStart == nil { runStart = i }
        } else if let from = runStart {
            if i - from >= minSilenceWindows {
                silences.append((Double(from) * hop, min(duration, Double(i) * hop)))
            }
            runStart = nil
        }
    }

    // 2. Il complemento sono le clip, scartando quelle troppo corte.
    var raw: [(start: Double, end: Double)] = []
    var cursor = 0.0
    for silence in silences {
        if silence.start - cursor >= s.minClip { raw.append((cursor, silence.start)) }
        cursor = silence.end
    }
    if duration - cursor >= s.minClip { raw.append((cursor, duration)) }

    // 3. Margine ai bordi, mai oltre metà del silenzio adiacente: così due clip
    //    non si sovrappongono mai, qualunque valore abbia il padding.
    return raw.enumerated().map { index, range in
        let previousEnd = index > 0 ? raw[index - 1].end : 0
        let nextStart = index + 1 < raw.count ? raw[index + 1].start : duration
        let head = min(s.padding, (range.start - previousEnd) / 2)
        let tail = min(s.padding, (nextStart - range.end) / 2)
        return (max(0, range.start - head), min(duration, range.end + tail))
    }
}
