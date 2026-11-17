import Foundation

/// Explicit local diagnostics only; normal launches never write pointer data.
@MainActor
enum HoverDiagnostics {
    private static let output: FileHandle? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--hover-trace"), args.count > index + 1 else { return nil }
        let url = URL(fileURLWithPath: args[index + 1])
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    static func record(_ values: @autoclosure () -> [String: Any]) {
        guard let output, let data = try? JSONSerialization.data(withJSONObject: values(), options: [.sortedKeys]) else { return }
        try? output.write(contentsOf: data + Data([10]))
    }
}
