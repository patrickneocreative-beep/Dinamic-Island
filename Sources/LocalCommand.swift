import Foundation
import Darwin

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let timedOut: Bool
}

enum LocalCommand {
    /// Executes argument arrays directly. User names and paths never enter a shell.
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 20) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try runSynchronously(executable, arguments: arguments, timeout: timeout)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func runSynchronously(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("isla-command-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try FileHandle(forUpdating: url)
            defer { try? file.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = file
            process.standardError = file
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                let stop = Date().addingTimeInterval(1)
                while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try file.seek(toOffset: 0)
            let bytes = try file.read(upToCount: 262_144) ?? Data()
            return CommandResult(status: process.terminationStatus, output: String(decoding: bytes, as: UTF8.self), timedOut: timedOut)
    }
}
