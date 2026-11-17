import SwiftUI

struct LyricsPane: View {
    @ObservedObject var service: LyricsService
    let position: Double
    let hasTrack: Bool
    let importFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if service.status == .available {
                let index = service.activeIndex(at: position)
                let current = index.map { service.lines[$0].text } ?? ""
                let previous = index.flatMap { $0 > 0 ? service.lines[$0 - 1].text : nil } ?? ""
                let next = index.map { $0 + 1 < service.lines.count ? service.lines[$0 + 1].text : "" } ?? service.lines.first?.text ?? ""
                Text(previous.isEmpty ? " " : previous).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3)).lineLimit(1)
                Text(current.isEmpty ? (index == nil ? "Introducción" : "♪") : current)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(current.isEmpty ? 0.5 : 0.95))
                    .lineLimit(2).minimumScaleFactor(0.85).frame(minHeight: 29, alignment: .leading)
                Text(next.isEmpty ? " " : next).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3)).lineLimit(1)
                HStack {
                    Text(service.source).font(.system(size: 7)).foregroundStyle(.white.opacity(0.23))
                    Spacer()
                    Menu {
                        Button("Adelantar letra 0,5 s") { service.adjustment += 0.5 }
                        Button("Retrasar letra 0,5 s") { service.adjustment -= 0.5 }
                        Button("Restablecer sincronización") { service.adjustment = 0 }
                        Divider()
                        Button("Cargar archivo LRC…", action: importFile)
                    } label: { Image(systemName: "ellipsis").font(.system(size: 9)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.mini).fixedSize()
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                Image(systemName: "text.quote").font(.system(size: 16, weight: .light)).foregroundStyle(.white.opacity(0.25))
                Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                if hasTrack && service.status != .loading {
                    HStack(spacing: 10) {
                        Button("Cargar .lrc", action: importFile)
                        if service.status == .failed { Button("Reintentar") { service.retry() } }
                    }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letra sincronizada")
    }

    private var statusText: String {
        guard hasTrack else { return "Letra de la canción" }
        return switch service.status {
        case .loading: "Buscando letra…"
        case .instrumental: "Instrumental"
        case .failed: "No se pudo cargar la letra"
        case .unavailable: "Sin letra sincronizada"
        default: "Letra de la canción"
        }
    }
}
