import AppKit
import Quartz

enum ShelfFileOperation {
    static func rename(_ url: URL, to name: String) throws -> URL {
        guard url.isFileURL, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw CocoaError(.fileWriteInvalidFileName) }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if target.standardizedFileURL == url.standardizedFileURL { return url }
        // moveItem fails on a collision. Never replace another file.
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
    static func compress(_ url: URL, to destination: URL) async throws -> URL {
        guard url.isFileURL, destination.isFileURL, FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let source = url.resolvingSymlinksInPath().standardizedFileURL.path
        let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard !target.hasPrefix(source + "/"), target != source else { throw CocoaError(.fileWriteInvalidFileName) }
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".isla-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temp) }
        var directory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        var arguments = ["-c", "-k", "--sequesterRsrc"]
        if directory.boolValue { arguments.append("--keepParent") }
        arguments += [url.path, temp.path]
        let result = try await LocalCommand.run("/usr/bin/ditto", arguments: arguments, timeout: 300)
        guard result.status == 0, !result.timedOut else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
}

@MainActor final class FileActions: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate, @preconcurrency NSSharingServicePickerDelegate {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private weak var model: IslandModel?
    private var previewURL: URL?
    private var picker: NSSharingServicePicker?
    init(model: IslandModel) { self.model = model }

    func preview(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path), let panel = QLPreviewPanel.shared() else { message = "Este archivo cambió de ubicación."; return }
        previewURL = url
        model?.interacting = true
        model?.panel?.previewController = self
        model?.panel?.makeKey()
        panel.updateController()
        panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    func beginPreview(_ panel: QLPreviewPanel) { panel.dataSource = self; panel.delegate = self }
    func endPreview(_ panel: QLPreviewPanel) {
        panel.dataSource = nil; panel.delegate = nil
        previewURL = nil; model?.interacting = false
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURL as NSURL? }
    func windowWillClose(_ notification: Notification) { previewURL = nil; model?.interacting = false }
    func rename(_ url: URL) {
        guard let model else { return }
        model.interacting = true
        defer { model.interacting = false }
        let alert = NSAlert()
        alert.messageText = "Renombrar archivo"
        alert.informativeText = "Se cambiará el nombre del archivo original. Conserva la extensión para que abra correctamente."
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Renombrar"); alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let target = try ShelfFileOperation.rename(url, to: field.stringValue)
            model.files = Array(NSOrderedSet(array: model.files.map { $0 == url ? target : $0 })) as? [URL] ?? model.files
            if model.shortcutInput == url { model.shortcutInput = target }
            message = "Nombre actualizado."
        } catch { message = "No se pudo renombrar. Revisa el nombre, los permisos y si ya existe otro archivo igual." }
    }
    func compress(_ url: URL) {
        guard !busy, let model else { return }
        model.interacting = true
        let panel = NSSavePanel()
        panel.title = "Crear archivo ZIP"
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".zip"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.allowedContentTypes = [.zip]
        panel.begin { [weak self, weak model] result in
            model?.interacting = false
            guard result == .OK, let destination = panel.url, let self else { return }
            self.busy = true; self.message = "Comprimiendo…"
            Task {
                defer { self.busy = false }
                do {
                    let zip = try await ShelfFileOperation.compress(url, to: destination)
                    // Background completion only updates shared data; it never opens a display.
                    if let model, !model.files.contains(zip) { model.files.append(zip) }
                    self.message = "ZIP añadido a la bandeja."
                } catch { self.message = "No se pudo crear el ZIP. Elige un nombre nuevo y una carpeta con permiso de escritura." }
            }
        }
    }
    func share(_ url: URL, from view: NSView) {
        guard FileManager.default.fileExists(atPath: url.path) else { message = "Este archivo cambió de ubicación."; return }
        model?.interacting = true
        picker = NSSharingServicePicker(items: [url])
        picker?.delegate = self
        picker?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        model?.interacting = false; picker = nil
    }
}
