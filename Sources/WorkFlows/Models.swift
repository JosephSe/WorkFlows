import Foundation

enum StepKind: String, Codable, CaseIterable, Identifiable {
    case openApp, quitApp, disconnectVPN, openURL, bluetoothConnect, audioOutput, setVolume, runShortcut, runShell, wait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openApp: "Open App"
        case .quitApp: "Quit App"
        case .disconnectVPN: "Disconnect Tunnelblick VPN"
        case .openURL: "Open URL"
        case .bluetoothConnect: "Connect Bluetooth Device"
        case .audioOutput: "Set Audio Output"
        case .setVolume: "Set Volume"
        case .runShortcut: "Run Shortcut"
        case .runShell: "Run Shell Command"
        case .wait: "Wait"
        }
    }

    var symbol: String {
        switch self {
        case .openApp: "app.badge"
        case .quitApp: "xmark.app"
        case .disconnectVPN: "lock.open"
        case .openURL: "globe"
        case .bluetoothConnect: "headphones"
        case .audioOutput: "speaker.wave.2"
        case .setVolume: "slider.horizontal.3"
        case .runShortcut: "wand.and.stars"
        case .runShell: "terminal"
        case .wait: "hourglass"
        }
    }

    var hint: String? {
        switch self {
        case .quitApp: "Asks the app to quit, like ⌘Q. Apps with unsaved changes may still prompt and stay open. Not running counts as done."
        case .disconnectVPN: "Disconnects every active Tunnelblick connection. Does nothing if Tunnelblick isn't running. macOS asks once to let WorkFlows control Tunnelblick."
        case .bluetoothConnect: "Needs blueutil: brew install blueutil"
        case .audioOutput: "Needs switchaudio-osx: brew install switchaudio-osx. Retries for ~18s while the speaker connects."
        case .runShortcut: "For Focus / Do Not Disturb, make a Shortcut with the “Set Focus” action and pick it here."
        default: nil
        }
    }
}

/// One action in a workflow. The three generic fields are interpreted per `kind`:
///   openApp          primary = app name
///   quitApp          primary = app name
///   openURL          primary = URL, secondary = browser app name ("" = system default)
///   bluetoothConnect primary = device address, secondary = display name
///   audioOutput      primary = output device name
///   setVolume        amount  = 0...100
///   runShortcut      primary = shortcut name
///   runShell         primary = command (run with zsh -lc)
///   wait             amount  = seconds
struct Step: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: StepKind
    var isEnabled = true
    var primary = ""
    var secondary = ""
    var amount = 0.0

    static func new(_ kind: StepKind) -> Step {
        switch kind {
        case .wait: Step(kind: kind, amount: 5)
        case .setVolume: Step(kind: kind, amount: 30)
        default: Step(kind: kind)
        }
    }

    var summary: String {
        switch kind {
        case .openApp: "Open \(primary)"
        case .quitApp: "Quit \(primary)"
        case .disconnectVPN: "Disconnect Tunnelblick VPN"
        case .openURL: secondary.isEmpty ? "Open \(primary)" : "Open \(primary) in \(secondary)"
        case .bluetoothConnect: "Connect \(secondary.isEmpty ? primary : secondary)"
        case .audioOutput: "Audio output → \(primary)"
        case .setVolume: "Volume \(Int(amount))%"
        case .runShortcut: "Shortcut “\(primary)”"
        case .runShell: "Shell: \(primary.prefix(40))"
        case .wait: "Wait \(Int(amount))s"
        }
    }
}

struct Workflow: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol = "bolt.fill"
    var steps: [Step] = []

    static let stopWork = Workflow(name: "Stop Work", symbol: "moon.fill", steps: [
        Step(kind: .quitApp, primary: "Microsoft Teams"),
        Step(kind: .quitApp, primary: "Slack"),
        Step(kind: .disconnectVPN),
        Step(kind: .quitApp, isEnabled: false, primary: "Microsoft Outlook"),
        Step(kind: .runShortcut, isEnabled: false, primary: "Personal Focus"),
    ])

    /// Seeded on first launch. Steps that need machine-specific values start disabled.
    static let defaults: [Workflow] = [
        Workflow(name: "Start Work", symbol: "briefcase.fill", steps: [
            Step(kind: .openURL, primary: "https://outlook.office.com/mail", secondary: "Microsoft Edge"),
            Step(kind: .openApp, primary: "Microsoft Teams"),
            Step(kind: .openApp, primary: "Slack"),
            Step(kind: .bluetoothConnect, isEnabled: false),
            Step(kind: .audioOutput, isEnabled: false),
            Step(kind: .setVolume, amount: 30),
            Step(kind: .runShortcut, isEnabled: false, primary: "Work Focus"),
        ]),
        Workflow(name: "Start Timepass", symbol: "gamecontroller.fill", steps: [
            Step(kind: .openURL, primary: "https://www.youtube.com"),
            Step(kind: .bluetoothConnect, isEnabled: false),
            Step(kind: .audioOutput, isEnabled: false),
            Step(kind: .setVolume, amount: 50),
        ]),
        stopWork,
    ]
}

struct Choice: Identifiable, Hashable {
    var label: String
    var value: String
    var id: String { value }
}
