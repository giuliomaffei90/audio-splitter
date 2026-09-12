// Verifica della logica di taglio. Esegui:
//   swiftc -O -o /tmp/check AudioSplitter/SilenceDetector.swift check/main.swift && /tmp/check
import Foundation

let hop = envelopeHop  // 0.01 s

/// Costruisce un inviluppo: (secondi, livello) ripetuti.
func envelope(_ blocks: [(Double, Float)]) -> [Float] {
    blocks.flatMap { Array(repeating: $0.1, count: Int(($0.0 / hop).rounded())) }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 0.011) -> Bool { abs(a - b) < tol }

var settings = SplitSettings()  // -40 dB, 0.5 s, 0.1 s pad, 0.15 s min

// 1. Suono | silenzio lungo | suono -> due clip, con margine applicato.
do {
    let env = envelope([(1.0, 0.5), (1.0, 0.0), (1.0, 0.5)])
    let r = nonSilentRanges(rms: env, hop: hop, duration: 3.0, settings: settings)
    precondition(r.count == 2, "attese 2 clip, ottenute \(r.count)")
    precondition(approx(r[0].start, 0.0) && approx(r[0].end, 1.1), "clip 1 = \(r[0])")
    precondition(approx(r[1].start, 1.9) && approx(r[1].end, 3.0), "clip 2 = \(r[1])")
}

// 2. Un silenzio più corto di minSilence non taglia nulla.
do {
    let env = envelope([(1.0, 0.5), (0.2, 0.0), (1.0, 0.5)])
    let r = nonSilentRanges(rms: env, hop: hop, duration: 2.2, settings: settings)
    precondition(r.count == 1 && approx(r[0].start, 0) && approx(r[0].end, 2.2), "atteso 1 blocco unico, \(r)")
}

// 3. Le clip sotto minClip spariscono.
do {
    let env = envelope([(0.05, 0.5), (1.0, 0.0), (1.0, 0.5)])
    let r = nonSilentRanges(rms: env, hop: hop, duration: 2.05, settings: settings)
    precondition(r.count == 1, "il frammento da 50 ms doveva sparire, \(r)")
}

// 4. Padding enorme: le clip si toccano ma non si sovrappongono mai.
do {
    settings.padding = 10
    let env = envelope([(1.0, 0.5), (1.0, 0.0), (1.0, 0.5)])
    let r = nonSilentRanges(rms: env, hop: hop, duration: 3.0, settings: settings)
    precondition(r.count == 2 && r[0].end <= r[1].start, "sovrapposizione: \(r)")
    precondition(approx(r[0].start, 0) && approx(r[1].end, 3.0), "bordi del file non rispettati: \(r)")
    settings.padding = 0.1
}

// 5. Silenzio totale -> nessuna clip. File tutto suono -> una clip sola.
do {
    precondition(nonSilentRanges(rms: envelope([(3.0, 0.0)]), hop: hop, duration: 3, settings: settings).isEmpty)
    let full = nonSilentRanges(rms: envelope([(3.0, 0.5)]), hop: hop, duration: 3, settings: settings)
    precondition(full.count == 1 && approx(full[0].start, 0) && approx(full[0].end, 3))
}

// 6. La soglia conta: -6 dB rende "silenzio" un livello 0.3.
do {
    settings.thresholdDB = -6
    let env = envelope([(1.0, 0.9), (1.0, 0.3), (1.0, 0.9)])
    precondition(nonSilentRanges(rms: env, hop: hop, duration: 3, settings: settings).count == 2, "soglia ignorata")
    settings.thresholdDB = -40
}

print("ok — 6 verifiche passate")
