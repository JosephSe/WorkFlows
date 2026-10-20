import AppKit

enum StepOutcome {
    case ok
    case failed(String)
}

/// Executes a single step. Deliberately not main-actor isolated so process waits never block the UI.
enum StepExecutor {
    static func execute(_ step: Step) async -> StepOutcome {
        let primary = step.primary.trimmingCharacters(in: .whitespacesAndNewlines)

        switch step.kind {
        case .wait:
            try? await Task.sleep(for: .seconds(step.amount))
            return .ok

        case .openApp:
            guard !primary.isEmpty else { return notConfigured }
            return outcome(await Shell.run("/usr/bin/open", ["-a", primary]))

        case .quitApp:
            guard !primary.isEmpty else { return notConfigured }
            return await quitApp(named: primary)

        case .disconnectVPN:
            return await disconnectTunnelblick()

        case .openURL:
            guard !primary.isEmpty else { return notConfigured }
            let url = primary.contains("://") ? primary : "https://\(primary)"
            var args: [String] = []
            if !step.secondary.isEmpty { args += ["-a", step.secondary] }
            args.append(url)
            return outcome(await Shell.run("/usr/bin/open", args))

        case .bluetoothConnect:
            guard !primary.isEmpty else { return notConfigured }
            return await connectBluetooth(primary)

        case .audioOutput:
            guard !primary.isEmpty else { return notConfigured }
            return await switchAudioOutput(to: primary)

        case .setVolume:
            let level = max(0, min(100, Int(step.amount)))
            return outcome(await Shell.run("/usr/bin/osascript", ["-e", "set volume output volume \(level)"]))

        case .runShortcut:
            guard !primary.isEmpty else { return notConfigured }
            return outcome(await Shell.run("/usr/bin/shortcuts", ["run", primary], timeout: 120))

        case .runShell:
            guard !primary.isEmpty else { return notConfigured }
            return outcome(await Shell.run("/bin/zsh", ["-lc", primary], timeout: 120))
        }
    }

    private static let notConfigured = StepOutcome.failed("not configured")

    private static func outcome(_ result: ShellResult) -> StepOutcome {
        if result.ok { return .ok }
        let message = result.output.isEmpty ? "exit code \(result.status)" : String(result.output.prefix(200))
        return .failed(message)
    }

    /// Asks every running copy of the app to quit (like ⌘Q) and waits briefly for it to go.
    /// Matches by display name or bundle id. An app that isn't running counts as done.
    private static func quitApp(named name: String) async -> StepOutcome {
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                || $0.bundleIdentifier?.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !matches.isEmpty else { return .ok }

        for app in matches { app.terminate() }
        for _ in 0..<20 {
            if matches.allSatisfy(\.isTerminated) { return .ok }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return .failed("still running after 10s (it may be asking to save changes)")
    }

    /// Checked first so AppleScript doesn't launch Tunnelblick just to tell it to disconnect.
    private static func disconnectTunnelblick() async -> StepOutcome {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "net.tunnelblick.tunnelblick"
        }
        guard running else { return .ok }
        return outcome(await Shell.run("/usr/bin/osascript", ["-e", "tell application \"Tunnelblick\" to disconnect all"]))
    }

    private static func connectBluetooth(_ address: String) async -> StepOutcome {
        let power = await Shell.tool("blueutil", ["--power"])
        if power.status == 127 { return .failed("blueutil not installed (brew install blueutil)") }
        if power.output == "0" {
            _ = await Shell.tool("blueutil", ["--power", "1"])
            try? await Task.sleep(for: .seconds(2))
        }

        let connect = await Shell.tool("blueutil", ["--connect", address])
        if !connect.ok { return outcome(connect) }

        for _ in 0..<15 {
            let state = await Shell.tool("blueutil", ["--is-connected", address])
            if state.output == "1" { return .ok }
            try? await Task.sleep(for: .seconds(1))
        }
        return .failed("device did not report connected within 15s")
    }

    /// A freshly connected Bluetooth speaker takes a few seconds to appear as an audio device.
    private static func switchAudioOutput(to device: String) async -> StepOutcome {
        var last = ShellResult(status: 1, output: "")
        for _ in 0..<12 {
            last = await Shell.tool("SwitchAudioSource", ["-t", "output", "-s", device])
            if last.ok { return .ok }
            if last.status == 127 { return .failed("SwitchAudioSource not installed (brew install switchaudio-osx)") }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return outcome(last)
    }
}

struct LogLine: Identifiable {
    enum Level { case info, ok, failed }
    let id = UUID()
    let level: Level
    let text: String
}

@MainActor
final class Runner: ObservableObject {
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var runningName: String?
    @Published private(set) var lastSummary: String?

    private var task: Task<Void, Never>?

    var isRunning: Bool { runningName != nil }

    func run(_ workflow: Workflow) {
        guard !isRunning else { return }
        let steps = workflow.steps.filter(\.isEnabled)
        guard !steps.isEmpty else {
            log = [LogLine(level: .failed, text: "“\(workflow.name)” has no enabled steps")]
            return
        }

        runningName = workflow.name
        log = [LogLine(level: .info, text: "Running “\(workflow.name)”")]

        task = Task {
            var failures = 0
            for step in steps {
                if Task.isCancelled { break }
                switch await StepExecutor.execute(step) {
                case .ok:
                    log.append(LogLine(level: .ok, text: step.summary))
                case .failed(let reason):
                    failures += 1
                    log.append(LogLine(level: .failed, text: "\(step.summary): \(reason)"))
                }
            }

            let summary: String
            if Task.isCancelled {
                summary = "“\(workflow.name)” cancelled"
            } else if failures == 0 {
                summary = "“\(workflow.name)” finished"
            } else {
                summary = "“\(workflow.name)” finished with \(failures) failed step\(failures == 1 ? "" : "s")"
            }
            log.append(LogLine(level: failures == 0 ? .info : .failed, text: summary))
            lastSummary = summary
            runningName = nil
            task = nil
            Self.notify(summary)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private static func notify(_ text: String) {
        let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
        Task {
            _ = await Shell.run("/usr/bin/osascript", ["-e", "display notification \"\(safe)\" with title \"WorkFlows\""])
        }
    }
}
