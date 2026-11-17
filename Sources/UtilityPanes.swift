import SwiftUI

private typealias StoredState<Value> = SwiftUI.State<Value>

struct UtilityButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(configuration.isPressed ? 0.17 : 0.08), in: Capsule())
    }
}

struct ClipboardPane: View {
    @ObservedObject var service: ClipboardService
    @StoredState private var search = ""
    private var matches: [ClipboardEntry] {
        service.sorted.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.text?.localizedCaseInsensitiveContains(search) ?? false) }
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                TextField("Buscar en el portapapeles", text: $search).textFieldStyle(.plain).font(.system(size: 11))
                    .accessibilityLabel("Buscar en el portapapeles")
                Button(service.enabled ? "Pausar" : "Activar historial") { service.setEnabled(!service.enabled) }.buttonStyle(UtilityButton())
                Button { service.clearRecent() } label: { Image(systemName: "trash").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Borrar recientes; conserva lo fijado").disabled(service.entries.allSatisfy(\.pinned))
            }
            if matches.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 24, weight: .light)).foregroundStyle(.white.opacity(0.4))
                    Text(!search.isEmpty ? "Sin coincidencias" : service.enabled ? "Copia texto, enlaces o imágenes para verlos aquí." : "Activa el historial para guardar tus próximas copias.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matches) { item in
                            HStack(spacing: 8) {
                                if let image = item.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 26).clipShape(RoundedRectangle(cornerRadius: 4)) }
                                else { Image(systemName: item.symbol).foregroundStyle(.white.opacity(0.45)).frame(width: 28) }
                                Button { service.copy(item) } label: {
                                    Text(item.title).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Copiar de nuevo")
                                Button { service.togglePin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin").frame(width: 22, height: 24) }
                                    .buttonStyle(.plain).foregroundStyle(.white.opacity(item.pinned ? 0.9 : 0.4)).help(item.pinned ? "Desfijar" : "Fijar y guardar en este Mac")
                                Button { service.remove(item.id) } label: { Image(systemName: "xmark").frame(width: 18, height: 24) }
                                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.4)).help("Eliminar del historial")
                            }.font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                                .onDrag { item.provider }
                        }
                    }
                }
            }
            Text(service.message ?? "Los recientes viven en esta sesión; solo lo fijado se guarda en este Mac.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var service: ShortcutsService
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                if let input = model.shortcutInput {
                    Image(systemName: "doc").foregroundStyle(.white.opacity(0.5))
                    Text(input.lastPathComponent).lineLimit(1).help(input.path)
                    Button { model.shortcutInput = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Quitar archivo de entrada")
                } else { Text("Tus favoritos, a un clic").foregroundStyle(.white.opacity(0.5)) }
                Spacer(minLength: 5)
                Button("Abrir Atajos") { service.openApp() }.buttonStyle(UtilityButton())
                Button { service.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Actualizar Atajos").disabled(service.loading || service.runningID != nil)
            }.font(.system(size: 10))
            if service.loading && service.items.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.items.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 23, weight: .light))
                    Text("Crea un atajo en la app Atajos y pulsa actualizar.").font(.system(size: 11))
                }.foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(service.sorted) { item in
                            HStack(spacing: 6) {
                                Button { service.run(item, input: model.shortcutInput) } label: {
                                    HStack(spacing: 7) {
                                        if service.runningID == item.id { ProgressView().controlSize(.mini).frame(width: 13, height: 13) }
                                        else { Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
                                        Text(item.name).font(.system(size: 11)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.frame(height: 30).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(service.runningID != nil).help("Ejecutar «\(item.name)»")
                                Button { service.toggleFavorite(item) } label: {
                                    Image(systemName: service.favorites.contains(item.id) ? "star.fill" : "star").font(.system(size: 10)).frame(width: 20, height: 30)
                                }.buttonStyle(.plain).foregroundStyle(.white.opacity(service.favorites.contains(item.id) ? 0.9 : 0.3)).help("Favorito")
                            }.padding(.horizontal, 8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            Text(service.message ?? "Marca la estrella para poner un atajo primero. Se ejecuta solo al pulsarlo.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).help(service.message ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FileShelfPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var actions: FileActions
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(model.files.isEmpty ? "Bandeja de archivos" : "\(model.files.count) en la bandeja").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                if actions.busy { ProgressView().controlSize(.mini) }
                Spacer()
                Button("Añadir") { model.chooseFiles() }.buttonStyle(UtilityButton())
            }
            if model.files.isEmpty {
                Button { model.chooseFiles() } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 23, weight: .light))
                        Text("Acerca un archivo a la isla y suéltalo aquí.").font(.system(size: 11))
                    }.foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.files, id: \.self) { url in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                                Button { actions.preview(url) } label: {
                                    Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Vista previa · \(url.path)")
                                Button { model.useInShortcut(url) } label: { Image(systemName: "square.stack.3d.up").frame(width: 23, height: 26) }
                                    .buttonStyle(.plain).help("Usar este archivo en Atajos")
                                ShareFileButton(url: url, actions: actions).frame(width: 25, height: 26)
                                Menu {
                                    Button("Vista previa") { actions.preview(url) }
                                    Button("Abrir archivo") { model.openFile(url) }
                                    Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    Divider()
                                    Button("Renombrar…") { actions.rename(url) }
                                    Button("Comprimir en ZIP…") { actions.compress(url) }.disabled(actions.busy)
                                    Divider()
                                    Button("Quitar de la bandeja") { model.files.removeAll { $0 == url } }
                                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 24) }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Acciones del archivo")
                            }.font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        }
                    }
                }
            }
            Text(actions.message ?? "Arrastra para llevarte un archivo. Quitar de la bandeja conserva el original.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).help(actions.message ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ShareFileButton: NSViewRepresentable {
    let url: URL
    let actions: FileActions
    func makeCoordinator() -> Coordinator { Coordinator(url: url, actions: actions) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Compartir archivo")!, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.isBordered = false; button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Compartir archivo"
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) { context.coordinator.url = url }
    @MainActor final class Coordinator: NSObject {
        var url: URL
        let actions: FileActions
        init(url: URL, actions: FileActions) { self.url = url; self.actions = actions }
        @objc func share(_ sender: NSButton) { actions.share(url, from: sender) }
    }
}
