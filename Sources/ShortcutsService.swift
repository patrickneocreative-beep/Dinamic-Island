import AppKit

struct ShortcutItem: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor final class ShortcutsService: ObservableObject {
    @Published private(set) var items: [ShortcutItem] = []
    @Published private(set) var favorites: Set<String>
    @Published private(set) var loading = false
    @Published private(set) var runningID: String?
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private let executable: String
    private let preview: Bool
    private var refreshedAt: Date?

    init(preview: Bool = false, defaults: UserDefaults = .standard, executable: String = "/usr/bin/shortcuts") {
        self.preview = preview; self.defaults = defaults; self.executable = executable
        favorites = preview ? [] : Set(defaults.stringArray(forKey: "shortcuts.favorites") ?? [])
    }
    var sorted: [ShortcutItem] {
        items.sorted { favorites.contains($0.id) != favorites.contains($1.id) ? favorites.contains($0.id) : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func parse(_ output: String) -> [ShortcutItem] {
        guard let regex = try? NSRegularExpression(pattern: #"^(.*) \(([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\)$"#) else { return [] }
        var seen = Set<String>()
        return output.components(separatedBy: .newlines).compactMap { line in
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line), let idRange = Range(match.range(at: 2), in: line) else { return nil }
            let id = String(line[idRange]).uppercased()
            guard seen.insert(id).inserted else { return nil }
            return ShortcutItem(id: id, name: String(line[name]))
        }
    }
    func refresh(force: Bool = false) {
        guard !preview, !loading, runningID == nil, force || refreshedAt == nil || Date().timeIntervalSince(refreshedAt!) > 60 else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let result = try await LocalCommand.run(executable, arguments: ["list", "--show-identifiers"])
                guard result.status == 0, !result.timedOut else { message = "No se pudieron cargar tus Atajos. Abre Atajos e inténtalo de nuevo."; return }
                items = Self.parse(result.output)
                refreshedAt = Date()
                message = nil
            } catch { message = "No se pudo acceder a Atajos en este Mac." }
        }
    }
    func toggleFavorite(_ item: ShortcutItem) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        if !preview { defaults.set(Array(favorites).sorted(), forKey: "shortcuts.favorites") }
    }
    func run(_ item: ShortcutItem, input: URL? = nil) {
        guard !preview, runningID == nil, items.contains(item) else { return }
        if let input, !input.isFileURL || !FileManager.default.fileExists(atPath: input.path) {
            message = "El archivo ya no está disponible. Vuelve a añadirlo a la bandeja."; return
        }
        runningID = item.id
        message = "Ejecutando «\(item.name)»…"
        var args = ["run", item.id]
        if let input { args += ["--input-path", input.path] }
        Task {
            defer { runningID = nil }
            do {
                let result = try await LocalCommand.run(executable, arguments: args, timeout: 300)
                if result.timedOut { message = "Atajos no respondió en cinco minutos. Revisa la app antes de volver a ejecutarlo." }
                else if result.status == 0 { message = "«\(item.name)» completado." }
                else { message = "«\(item.name)» no terminó. Revisa sus permisos o pasos en Atajos." }
            } catch { message = "No se pudo iniciar «\(item.name)»." }
        }
    }
    func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
}
