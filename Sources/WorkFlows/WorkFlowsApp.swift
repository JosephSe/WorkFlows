import SwiftUI

/// Receives `workflows://run/<id>` (sent by the Spotlight launcher apps), including on a cold launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let store = Store()
    @MainActor static let runner = Runner()

    private var launchedAt = Date()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAt = Date()
        Self.store.syncLaunchers()
    }

    /// A workflow URL that arrives while the app is starting up means a Spotlight launcher started it,
    /// so the app has no reason to stay: it quits once the workflow is done. If the app was already
    /// running (the user opened it, or it's a login item), it stays.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        let startedByLauncher = Date().timeIntervalSince(launchedAt) < 3
        for url in urls {
            guard let workflow = Launchers.workflow(for: url, in: Self.store.workflows) else { continue }
            Self.runner.run(workflow) {
                if startedByLauncher { NSApp.terminate(nil) }
            }
        }
        if startedByLauncher, !Self.runner.isRunning { NSApp.terminate(nil) }
    }
}

@main
struct WorkFlowsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppDelegate.store
    @StateObject private var runner = AppDelegate.runner
    @StateObject private var loginItem = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            ForEach(store.workflows) { workflow in
                Button {
                    runner.run(workflow)
                } label: {
                    Label(workflow.name, systemImage: workflow.symbol)
                }
                .disabled(runner.isRunning)
            }

            Divider()

            if let name = runner.runningName {
                Text("Running “\(name)”…")
                Button("Cancel") { runner.cancel() }
            } else if let summary = runner.lastSummary {
                Text(summary)
            }

            Divider()

            Button("Edit Workflows…") {
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.set($0) }
            ))
            if let error = loginItem.errorMessage {
                Text(error)
            }

            Divider()

            Button("Quit WorkFlows") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: runner.isRunning ? "hourglass.circle.fill" : "bolt.circle.fill")
        }

        Window("WorkFlows", id: "editor") {
            EditorView()
                .environmentObject(store)
                .environmentObject(runner)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 920, height: 640)
    }
}
