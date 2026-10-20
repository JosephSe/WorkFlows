import SwiftUI

@main
struct WorkFlowsApp: App {
    @StateObject private var store = Store()
    @StateObject private var runner = Runner()
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
