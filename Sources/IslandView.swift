import SwiftUI
import UniformTypeIdentifiers

private typealias StoredState<Value> = SwiftUI.State<Value>

struct IslandShell: Shape {
    var attached: Bool
    var expanded: Bool
    func path(in rect: CGRect) -> Path {
        guard attached else { return RoundedRectangle(cornerRadius: expanded ? 28 : 4, style: .continuous).path(in: rect) }
        let lip: CGFloat = 9
        let lower: CGFloat = min(26, max(10, rect.height / 6))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - lip, y: rect.minY + lip), control: CGPoint(x: rect.maxX - lip, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - lip, y: rect.maxY - lower))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - lip - lower, y: rect.maxY), control: CGPoint(x: rect.maxX - lip, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + lip + lower, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + lip, y: rect.maxY - lower), control: CGPoint(x: rect.minX + lip, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + lip, y: rect.minY + lip))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + lip, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaService
    var snapshot = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editingNote: Bool
    @StoredState private var scrubbing = false
    @StoredState private var scrubPosition = 0.0

    private var shell: IslandShell { IslandShell(attached: true, expanded: model.expanded) }
    private var elapsed: Double { scrubbing ? scrubPosition : media.track.elapsed(at: model.now) }

    var body: some View {
        GeometryReader { geometry in
          ZStack(alignment: .top) {
            if model.expanded {
                VStack(spacing: 8) {
                    navigation.frame(height: model.toolbarHeight)
                    content.frame(height: model.contentHeight, alignment: .top)
                }
                .padding(.horizontal, 23)
                .padding(.top, model.topInset)
                .padding(.bottom, 12)
                .frame(width: model.expandedWidth, alignment: .top)
                .transition(.opacity)
            } else if model.hasNotch {
                CompactStatus(model: model, media: media, phones: model.phones)
                    .transition(.opacity)
            } else {
                Color.clear
            }
          }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: model.expanded)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .background { IslandSurface(shape: shell, snapshot: snapshot, expanded: model.expanded) }
        .overlay {
            if model.dropTargeted { shell.fill(.white.opacity(0.035)).allowsHitTesting(false) }
        }
        .clipShape(shell)
        }
        .frame(width: snapshot ? model.width : nil, height: snapshot ? model.height : nil)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .contentShape(shell)
        .modifier(IslandInteractions(model: model, snapshot: snapshot))
        .onChange(of: model.dropTargeted) { _, targeted in if targeted { model.select(.files); model.setExpanded(true) } }
        .onChange(of: model.tab) { _, _ in editingNote = false; scrubbing = false; model.interacting = false }
        .onChange(of: media.track.id) { _, _ in scrubbing = false }
        .onExitCommand { editingNote = false; model.close() }
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    Button { model.select(tab) } label: {
                        Image(systemName: tab.symbol).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(model.tab == tab ? 0.95 : 0.42))
                            .frame(width: 27, height: 23)
                            .background(.white.opacity(model.tab == tab ? 0.10 : 0), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).help(tab == .home ? "Controles" : tab.rawValue)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityIdentifier("tab-" + tab.rawValue)
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.hasNotch { Color.clear.frame(width: model.notchWidth + 18, height: 1).accessibilityHidden(true) }
            HStack(spacing: 7) {
                Text(model.tab == .home ? "Controles" : model.tab.rawValue)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin").font(.system(size: 10))
                        .foregroundStyle(.white.opacity(model.pinned ? 0.9 : 0.4)).frame(width: 22, height: 24)
                }.buttonStyle(.plain).help(model.pinned ? "Dejar de mantener abierto" : "Mantener abierto")
                Button { model.close() } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4)).frame(width: 22, height: 24)
                }.buttonStyle(.plain).help("Contraer · Esc")
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .home: home
        case .music: music
        case .focus: focus
        case .notes: notes
        case .files: FileShelfPane(model: model, actions: model.fileActions)
        case .calendar: CalendarPane(model: model, service: model.calendar)
        case .clipboard: ClipboardPane(service: model.data.clipboard)
        case .shortcuts: ShortcutsPane(model: model, service: model.data.shortcuts)
        }
    }

    private var home: some View {
        VStack(spacing: 8) {
            PowerOverview(model: model, phones: model.phones)
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                if model.canChangeVolume {
                    Slider(value: Binding(get: { model.volume }, set: model.setVolume), in: 0...1).tint(.white)
                        .accessibilityLabel("Volumen del Mac")
                    Text("\(Int(model.volume * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.5)).frame(width: 31)
                } else {
                    Text("Controla el volumen desde tu salida de audio.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            }
        }
    }

    private var music: some View {
        HStack(spacing: 15) {
            VStack(spacing: 7) {
                if media.track.exists {
                    HStack(spacing: 11) {
                        artwork.frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(media.track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(media.track.title)
                            Text(media.track.artist.isEmpty ? "Artista no disponible" : media.track.artist)
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).help(media.track.artist)
                            HStack(spacing: 4) {
                                sourceMenu
                                if !media.track.album.isEmpty {
                                    Text("·").foregroundStyle(.white.opacity(0.3))
                                    Text(media.track.album).lineLimit(1).foregroundStyle(.white.opacity(0.35)).help(media.track.album)
                                }
                            }.font(.system(size: 9))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 7) {
                            mediaButton("backward.end.fill", label: "Anterior", command: "previous track")
                            Button { media.command("playpause") } label: {
                                Image(systemName: media.track.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .semibold)).frame(width: 25, height: 27)
                            }.buttonStyle(.plain).accessibilityLabel(media.track.playing ? "Pausar" : "Reproducir").disabled(media.commandBusy)
                            mediaButton("forward.end.fill", label: "Siguiente", command: "next track")
                        }
                        VStack(spacing: 0) {
                            Slider(value: Binding(get: { elapsed }, set: { scrubPosition = $0 }), in: 0...max(1, media.track.duration)) { editing in
                                scrubbing = editing
                                model.interacting = editing
                                if editing { scrubPosition = media.track.elapsed(at: model.now) }
                                else { media.seek(to: scrubPosition) }
                            }
                            .tint(.white.opacity(0.85)).controlSize(.mini).disabled(media.track.duration <= 0)
                            .accessibilityLabel("Posición de reproducción")
                            HStack {
                                Text(TrackState.timeLabel(elapsed))
                                Spacer()
                                Text(media.track.duration > 0 ? "−" + TrackState.timeLabel(max(0, media.track.duration - elapsed)) : "En directo")
                            }.font(.system(size: 8)).monospacedDigit().foregroundStyle(.white.opacity(0.42))
                        }
                    }
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tu música, aquí").font(.system(size: 12, weight: .medium))
                            Text(media.message ?? "Abre tu reproductor y conecta ISLA.")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ForEach(MusicPlayer.allCases, id: \.self) { player in
                            Button(player.rawValue) {
                                if player.running { media.connect(player) } else { media.openPlayer(player); media.connect(player) }
                            }.buttonStyle(SmallGlassButton(snapshot: snapshot))
                        }
                        Spacer()
                    }
                }
            }.frame(width: (model.expandedWidth - 46) * 0.56, height: model.contentHeight, alignment: .center)
            Rectangle().fill(.white.opacity(0.09)).frame(width: 0.5, height: 82)
            LyricsPane(service: model.lyrics, position: elapsed, hasTrack: media.track.exists, importFile: model.chooseLyricsFile)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07))
            if let image = media.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.35))
                    if !media.artworkLoading { Text("Sin portada").font(.system(size: 7)).foregroundStyle(.white.opacity(0.35)) }
                }
            }
        }
        .frame(width: 60, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if let icon = media.sourceIcon {
                Image(nsImage: icon).resizable().frame(width: 17, height: 17)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4)).offset(x: 3, y: 3)
            }
        }
        .accessibilityLabel(media.artwork == nil ? "Portada no disponible" : "Portada de \(media.track.album)")
    }

    private var sourceMenu: some View {
        Menu {
            Button("Detectar reproductor automáticamente") { media.useAutomatic() }
            ForEach(MusicPlayer.allCases, id: \.self) { player in
                Button(player.rawValue) { media.connect(player) }
            }
            if let player = media.player {
                Divider()
                Button("Abrir \(player.rawValue)") { media.openPlayer(player) }
                Button("Desconectar") { media.disconnect() }
            }
        } label: {
            Text(media.player?.rawValue ?? "Reproductor")
        }
        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        .controlSize(.mini).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func mediaButton(_ symbol: String, label: String, command: String) -> some View {
        Button { media.command(command) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 27)
        }.buttonStyle(.plain).accessibilityLabel(label).disabled(media.commandBusy)
    }

    private var focus: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle().stroke(.white.opacity(0.09), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.008, model.focus.progress))
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(model.focus.label).font(.system(size: 24, weight: .light)).monospacedDigit()
            }.frame(width: 93, height: 93)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.focus.completed ? "Completado" : model.focus.running ? "En curso" : "Temporizador")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 5) {
                    ForEach([5, 25, 50], id: \.self) { minutes in
                        Button("\(minutes) min") { model.focus.select(minutes: minutes) }
                            .font(.system(size: 9)).buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.white.opacity(model.focus.duration == Double(minutes * 60) ? 0.16 : 0.06), in: Capsule())
                            .disabled(model.focus.running)
                    }
                }
                HStack(spacing: 12) {
                    Button(model.focus.running ? "Pausar" : "Iniciar") { model.focus.toggle() }
                        .buttonStyle(SmallGlassButton(snapshot: snapshot))
                    Button { model.focus.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)) }
                        .buttonStyle(.plain).help("Reiniciar")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                if model.note.isEmpty {
                    Text("Escribe una nota…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35)).padding(9)
                }
                if snapshot {
                    Text(model.note).font(.system(size: 12)).padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    TextEditor(text: $model.note).font(.system(size: 12)).scrollContentBackground(.hidden)
                        .focused($editingNote).padding(5).accessibilityLabel("Nota rápida")
                }
            }.background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            Text("Guardado en este Mac").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
        }
    }

}

private struct SmallGlassButton: ButtonStyle {
    var snapshot = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 12).padding(.vertical, 7)
            .glassControl(snapshot: snapshot, shape: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct IslandInteractions: ViewModifier {
    @ObservedObject var model: IslandModel
    let snapshot: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if snapshot { content }
        else {
            content.onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted, perform: model.drop)
        }
    }
}
