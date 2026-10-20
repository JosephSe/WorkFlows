import Foundation

struct ShellResult {
    let status: Int32
    let output: String
    var ok: Bool { status == 0 }
}

enum Shell {
    /// A GUI app inherits a bare PATH, so look in the usual Homebrew locations ourselves.
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func locate(_ tool: String) -> String? {
        searchPaths
            .map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `executable` off the main thread. stdout+stderr go to a temp file rather than a pipe,
    /// so a backgrounded child holding the descriptor open can't hang us. Killed after `timeout`.
    static func run(_ executable: String, _ args: [String] = [], timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: outURL.path, contents: nil)
                defer { try? FileManager.default.removeItem(at: outURL) }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                if let handle = try? FileHandle(forWritingTo: outURL) {
                    process.standardOutput = handle
                    process.standardError = handle
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, output: error.localizedDescription))
                    return
                }

                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                process.waitUntilExit()
                killer.cancel()

                let data = (try? Data(contentsOf: outURL)) ?? Data()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ShellResult(status: process.terminationStatus, output: text))
            }
        }
    }

    /// Runs a Homebrew-style tool by name; status 127 if it isn't installed.
    static func tool(_ name: String, _ args: [String], timeout: TimeInterval = 30) async -> ShellResult {
        guard let path = locate(name) else {
            return ShellResult(status: 127, output: "\(name) not found")
        }
        return await run(path, args, timeout: timeout)
    }
}
