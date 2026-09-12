import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AudioSplitterApp: App {
    var body: some Scene {
        WindowGroup("Audio Splitter") {
            ContentView().frame(minWidth: 680, minHeight: 460)
        }
        .defaultSize(width: 980, height: 680)
    }
}

/// Gli stessi colori dell'icona, tutti nella scala blu-azzurro.
/// Il suono è blu, la parte già riprodotta si accende in azzurro.
enum Palette {
    static let light = Color(red: 0.486, green: 0.784, blue: 0.980)  // azzurro chiaro
    static let glow = Color(red: 0.227, green: 0.541, blue: 0.847)   // blu medio
    static let mid = Color(red: 0.106, green: 0.373, blue: 0.769)    // blu pieno
    static let deep = Color(red: 0.039, green: 0.188, blue: 0.439)   // blu profondo
}

struct ContentView: View {
    @State private var model = SplitterModel()
    @State private var player = Player()
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            if model.fileName == nil {
                DropZone(isTargeted: isTargeted)
            } else {
                header
                Divider()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach($model.clips) { $clip in
                            ClipTile(clip: $clip, player: player, model: model)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .overlay { if model.isLoading { ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .overlay(alignment: .bottom) { errorBanner }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            player.stop()
            Task { await model.load(url: url) }
            return true
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.glow, lineWidth: 3).padding(4)
            }
        }
    }

    // MARK: - Barra superiore

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.fileName ?? "").font(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(model.clips.count) clip · \(model.selectedCount) selezionate")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutte") { setAll(true) }
                Button("Nessuna") { setAll(false) }
                Button("Esporta \(model.selectedCount)") { export() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.deep)
                    .disabled(model.selectedCount == 0)
            }
            HStack(spacing: 22) {
                knob("Soglia", value: $model.settings.thresholdDB, in: -70 ... -10, format: "%.0f dB")
                knob("Silenzio min", value: $model.settings.minSilence, in: 0.05...2, format: "%.2f s")
                knob("Margine", value: $model.settings.padding, in: 0...0.5, format: "%.2f s")
                knob("Clip min", value: $model.settings.minClip, in: 0.02...2, format: "%.2f s")
            }
        }
        .padding(16)
    }

    private func knob(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: value, in: range)
        }
        .frame(minWidth: 120)
    }

    private var errorBanner: some View {
        Group {
            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.red.opacity(0.9), in: .rect(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .padding(16)
                    .onTapGesture { model.errorMessage = nil }
            }
        }
    }

    // MARK: - Azioni

    private func setAll(_ selected: Bool) {
        for index in model.clips.indices { model.clips[index].isSelected = selected }
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Esporta qui"
        panel.message = "Scegli dove salvare le clip selezionate."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            if try model.export(to: directory) > 0 {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        } catch {
            model.errorMessage = "Esportazione non riuscita: \(error.localizedDescription)"
        }
    }
}

// MARK: - Schermata iniziale

private struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(LinearGradient(
                    colors: isTargeted ? [Palette.light, Palette.glow] : [Palette.mid, Palette.deep],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Trascina qui un file audio").font(.title2)
            Text("Viene diviso in clip usando i silenzi. WAV, AIFF, CAF, MP3, M4A.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }
}

// MARK: - Tile

private struct ClipTile: View {
    @Binding var clip: Clip
    let player: Player
    let model: SplitterModel

    @State private var isHovering = false

    private var isPlaying: Bool { player.playingID == clip.id }
    /// A riposo il pulsante resta defilato: la waveform è il soggetto, non il comando.
    private var isProminent: Bool { isPlaying || isHovering }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    clip.isSelected.toggle()
                } label: {
                    Image(systemName: clip.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(clip.isSelected ? Palette.mid : .secondary)
                }
                .buttonStyle(.plain)
                Text("Clip \(clip.number)").font(.callout.weight(.medium))
                Spacer()
                Text(String(format: "%.2f s", clip.duration))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            Waveform(peaks: clip.peaks, progress: isPlaying ? player.progress : nil, active: clip.isSelected)
                .frame(height: 68)
                .background {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(
                            colors: [Palette.light.opacity(0.20), Palette.mid.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(alignment: .center) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background {
                            Circle()
                                .fill((isPlaying ? Palette.deep : Palette.mid)
                                    .opacity(isProminent ? 1 : 0.6))
                                .shadow(color: .black.opacity(isProminent ? 0.25 : 0), radius: 4, y: 2)
                        }
                        .scaleEffect(isProminent ? 1 : 0.82)
                        .animation(.easeOut(duration: 0.13), value: isProminent)
                }
                .contentShape(.rect)
                .onHover { isHovering = $0 }
                .onTapGesture { player.toggle(clip, from: model) }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(
                    colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.025)],
                    startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(isPlaying ? Palette.glow : .clear, lineWidth: 2)
        }
        .opacity(clip.isSelected ? 1 : 0.5)
        .animation(.easeOut(duration: 0.15), value: clip.isSelected)
    }
}

private struct Waveform: View {
    let peaks: [Float]
    let progress: Double?
    let active: Bool

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let step = size.width / CGFloat(peaks.count)
            let width = max(1.5, step * 0.6)
            let middle = size.height / 2
            let playedUpTo = progress.map { $0 * Double(peaks.count) } ?? -1

            // Due path, due fill: il gradiente scorre sull'intera waveform
            // invece di ridipingersi per ogni singola barra.
            var pending = Path()
            var played = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(3, CGFloat(peak) * size.height * 0.88)
                let bar = CGRect(
                    x: CGFloat(index) * step + (step - width) / 2,
                    y: middle - height / 2,
                    width: width,
                    height: height
                )
                let rounded = Path(roundedRect: bar, cornerRadius: width / 2)
                if Double(index) < playedUpTo { played.addPath(rounded) } else { pending.addPath(rounded) }
            }

            let top = CGPoint(x: 0, y: 0)
            let bottom = CGPoint(x: 0, y: size.height)
            context.fill(pending, with: .linearGradient(
                Gradient(colors: active
                    ? [Palette.light, Palette.glow]
                    : [.secondary.opacity(0.4), .secondary.opacity(0.25)]),
                startPoint: top, endPoint: bottom))
            context.fill(played, with: .linearGradient(
                Gradient(colors: [Palette.mid, Palette.deep]),
                startPoint: top, endPoint: bottom))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
