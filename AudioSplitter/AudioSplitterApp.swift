import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AudioSplitterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 680, minHeight: 460)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            ToolbarCommands()
            ClipCommands()
        }
    }
}

// MARK: - Menu

/// I comandi della finestra in primo piano; `nil` = voce disattivata.
struct WindowActions {
    var open: () -> Void
    var showsInspector: Bool
    var toggleInspector: () -> Void
    var export: (() -> Void)?
    var selectAll: (() -> Void)?
    var selectNone: (() -> Void)?
}

extension FocusedValues {
    @Entry var windowActions: WindowActions?
}

/// La barra degli strumenti si può nascondere: ogni suo comando sta anche nei menu.
struct ClipCommands: Commands {
    @FocusedValue(\.windowActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Apri…") { actions?.open() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
            Button("Esporta…") { actions?.export?() }
                .keyboardShortcut("e")
                .disabled(actions?.export == nil)
        }
        // Al posto di InspectorCommands, che in italiano mostra "Inspector Show".
        CommandGroup(after: .sidebar) {
            Button(actions?.showsInspector == true ? "Nascondi opzioni" : "Mostra opzioni") {
                actions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Seleziona tutte le clip") { actions?.selectAll?() }
                .disabled(actions?.selectAll == nil)
            Button("Deseleziona tutte le clip") { actions?.selectNone?() }
                .disabled(actions?.selectNone == nil)
        }
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
    @State private var showsInspector = true
    @State private var isPicking = false
    /// Quale scelta è aperta: resta impostata finché il pannello risponde.
    @State private var pickingFolder = false

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        Group {
            if model.fileName == nil {
                DropZone(isTargeted: isTargeted, open: open)
            } else {
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
        .navigationTitle(model.fileName ?? "Nessun file")
        .navigationSubtitle(subtitle)
        .inspector(isPresented: $showsInspector) {
            SettingsForm(settings: $model.settings)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
        }
        .toolbar { toolbar }
        .fileImporter(isPresented: $isPicking,
                      allowedContentTypes: pickingFolder ? [.folder] : [.audio]) { result in
            guard case .success(let url) = result else { return }
            if pickingFolder { export(to: url) } else { load(url) }
        }
        .fileDialogConfirmationLabel(pickingFolder ? "Esporta qui" : "Apri")
        .fileDialogMessage(pickingFolder ? "Scegli dove salvare le clip selezionate." : "")
        .alert(model.failure?.title ?? "",
               isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
               presenting: model.failure) { _ in } message: { Text($0.message) }
        .focusedSceneValue(\.windowActions, WindowActions(
            open: open,
            showsInspector: showsInspector,
            toggleInspector: { showsInspector.toggle() },
            export: model.selectedCount > 0 ? chooseExportFolder : nil,
            selectAll: model.clips.isEmpty ? nil : { setAll(true) },
            selectNone: model.clips.isEmpty ? nil : { setAll(false) }))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.glow, lineWidth: 3).padding(4)
            }
        }
    }

    // MARK: - Barra degli strumenti

    private var subtitle: String {
        if model.isLoading { return "Analisi in corso…" }
        guard model.fileName != nil else { return "" }
        return "\(model.clips.count) clip · \(model.selectedCount) selezionate"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isLoading {
            ToolbarItem { ProgressView().controlSize(.small) }
                .withoutSharedBackground()
        }
        ToolbarItem {
            ControlGroup {
                Button("Tutte") { setAll(true) }
                    .help("Seleziona tutte le clip")
                Button("Nessuna") { setAll(false) }
                    .help("Deseleziona tutte le clip")
            }
            .disabled(model.clips.isEmpty)
        }
        ToolbarGap()
        ToolbarItem {
            Button("Esporta…", action: chooseExportFolder)
                .prominentButton()
                .disabled(model.selectedCount == 0)
                .help("Salva le clip selezionate come WAV")
        }
        ToolbarGap()
        ToolbarItem {
            Button { showsInspector.toggle() } label: {
                Label("Opzioni", systemImage: "sidebar.trailing")
            }
            .help(showsInspector ? "Nascondi le opzioni" : "Mostra le opzioni")
        }
    }

    // MARK: - Azioni

    private func open() {
        pickingFolder = false
        isPicking = true
    }

    private func load(_ url: URL) {
        player.stop()
        Task { await model.load(url: url) }
    }

    private func setAll(_ selected: Bool) {
        for index in model.clips.indices { model.clips[index].isSelected = selected }
    }

    private func chooseExportFolder() {
        pickingFolder = true
        isPicking = true
    }

    private func export(to directory: URL) {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        do {
            if try model.export(to: directory) > 0 {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        } catch {
            model.failure = Failure(title: "Impossibile esportare le clip", message: error.localizedDescription)
        }
    }
}

// MARK: - Opzioni

private struct SettingsForm: View {
    @Binding var settings: SplitSettings

    var body: some View {
        Form {
            Section {
                knob("Soglia", value: $settings.thresholdDB, in: -70 ... -10, digits: 0, unit: "dB",
                     help: "Il livello sotto cui il suono conta come silenzio.")
                knob("Silenzio minimo", value: $settings.minSilence, in: 0.05...2, digits: 2, unit: "s",
                     help: "Quanto deve durare un silenzio per dividere il file.")
                knob("Margine", value: $settings.padding, in: 0...0.5, digits: 2, unit: "s",
                     help: "Il silenzio lasciato ai due capi di ogni clip.")
                knob("Clip minima", value: $settings.minClip, in: 0.02...2, digits: 2, unit: "s",
                     help: "Le clip più corte vengono scartate.")
            } header: {
                Text("Divisione")
            } footer: {
                Text("Le clip si ricalcolano mentre muovi i cursori.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func knob(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                      digits: Int, unit: String, help: String) -> some View {
        let text = "\(value.wrappedValue.formatted(.number.precision(.fractionLength(digits)))) \(unit)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) { Text(title) }
                .labelsHidden()
                .accessibilityValue(text)
        }
        .help(help)
    }
}

// MARK: - Schermata iniziale

private struct DropZone: View {
    let isTargeted: Bool
    let open: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Trascina qui un file audio")
            } icon: {
                Image(systemName: "waveform")
                    .foregroundStyle(LinearGradient(
                        colors: isTargeted ? [Palette.light, Palette.glow] : [Palette.mid, Palette.deep],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        } description: {
            Text("Viene diviso in clip usando i silenzi. WAV, AIFF, CAF, MP3, M4A.")
        } actions: {
            Button("Scegli un file…", action: open)
        }
    }
}

// MARK: - Compatibilità

extension View {
    /// Vetro colorato per l'unica azione principale; pulsante pieno prima di macOS 26.
    @ViewBuilder func prominentButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }
}

extension ToolbarContent {
    /// Senza la capsula di vetro condivisa (es. lo spinner); prima di macOS 26 la capsula non c'è.
    @ToolbarContentBuilder func withoutSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) { sharedBackgroundVisibility(.hidden) } else { self }
    }
}

/// Spazio tra gruppi della barra su macOS 26; prima non ci sono gruppi di vetro da separare.
struct ToolbarGap: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
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
                .accessibilityLabel("Includi nell'esportazione")
                .accessibilityAddTraits(clip.isSelected ? .isSelected : [])
                .help(clip.isSelected ? "Escludi la clip dall'esportazione" : "Includi la clip nell'esportazione")
                Text("Clip \(clip.number)").font(.callout.weight(.medium))
                Spacer()
                Text("\(clip.duration.formatted(.number.precision(.fractionLength(2)))) s")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            Button { player.toggle(clip, from: model) } label: {
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Ferma la clip \(clip.number)" : "Riproduci la clip \(clip.number)")
            .onHover { isHovering = $0 }
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
