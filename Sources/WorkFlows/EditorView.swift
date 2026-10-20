import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let workflowSymbols = [
    "briefcase.fill", "bolt.fill", "gamecontroller.fill", "music.note", "moon.fill",
    "sun.max.fill", "house.fill", "laptopcomputer", "book.fill", "figure.run", "film.fill", "cup.and.saucer.fill",
]

struct EditorView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: Workflow.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.workflows) { workflow in
                    Label(workflow.name, systemImage: workflow.symbol)
                        .tag(workflow.id)
                        .contextMenu {
                            Button("Duplicate") { duplicate(workflow) }
                            Button("Delete", role: .destructive) { delete(workflow) }
                        }
                }
                .onMove { store.workflows.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button(action: add) { Label("New Workflow", systemImage: "plus") }
                }
            }
        } detail: {
            if let id = selection, store.workflows.contains(where: { $0.id == id }) {
                WorkflowDetail(workflow: binding(for: id))
                    .id(id)
            } else {
                ContentUnavailableView("Select a workflow", systemImage: "bolt.circle")
            }
        }
        .onAppear { selection = selection ?? store.workflows.first?.id }
    }

    // Look the workflow up by id on every access so a deleted row can never leave a dangling index.
    private func binding(for id: Workflow.ID) -> Binding<Workflow> {
        Binding(
            get: { store.workflows.first { $0.id == id } ?? Workflow(name: "") },
            set: { newValue in
                if let index = store.workflows.firstIndex(where: { $0.id == id }) {
                    store.workflows[index] = newValue
                }
            }
        )
    }

    private func add() {
        let workflow = Workflow(name: "New Workflow")
        store.workflows.append(workflow)
        selection = workflow.id
    }

    private func duplicate(_ workflow: Workflow) {
        var copy = workflow
        copy.id = UUID()
        copy.name += " Copy"
        copy.steps = copy.steps.map { var s = $0; s.id = UUID(); return s }
        store.workflows.append(copy)
        selection = copy.id
    }

    private func delete(_ workflow: Workflow) {
        store.workflows.removeAll { $0.id == workflow.id }
        if selection == workflow.id { selection = store.workflows.first?.id }
    }
}

struct WorkflowDetail: View {
    @Binding var workflow: Workflow
    @EnvironmentObject private var runner: Runner

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List {
                ForEach($workflow.steps) { $step in
                    StepRow(step: $step) {
                        workflow.steps.removeAll { $0.id == step.id }
                    }
                }
                .onMove { workflow.steps.move(fromOffsets: $0, toOffset: $1) }
            }

            HStack {
                Menu {
                    ForEach(StepKind.allCases) { kind in
                        Button {
                            workflow.steps.append(.new(kind))
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .fixedSize()
                Spacer()
                Text("Steps run top to bottom. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            Divider()
            LogView()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(workflowSymbols, id: \.self) { symbol in
                    Button { workflow.symbol = symbol } label: { Image(systemName: symbol) }
                }
            } label: {
                Image(systemName: workflow.symbol).font(.title2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField("Workflow name", text: $workflow.name)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            if runner.isRunning {
                Button("Cancel") { runner.cancel() }
            }
            Button {
                runner.run(workflow)
            } label: {
                Label(runner.isRunning ? "Running…" : "Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(runner.isRunning)
        }
        .padding()
    }
}

struct StepRow: View {
    @Binding var step: Step
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Enabled", isOn: $step.isEnabled)
                .labelsHidden()
            Image(systemName: step.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.kind.title).font(.headline)
                editor
                if let hint = step.kind.hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete step")
        }
        .padding(.vertical, 4)
        .opacity(step.isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var editor: some View {
        switch step.kind {
        case .openApp:
            HStack {
                TextField("App name, e.g. Slack", text: $step.primary)
                Button("Choose…") {
                    if let name = chooseAppName() { step.primary = name }
                }
            }

        case .openURL:
            TextField("https://outlook.office.com/mail", text: $step.primary)
            Picker("Browser", selection: $step.secondary) {
                Text("System default").tag("")
                ForEach(Browser.options(including: step.secondary), id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 320)

        case .bluetoothConnect:
            HStack {
                TextField("Device address, e.g. aa-bb-cc-dd-ee-ff", text: $step.primary)
                ChoiceMenu(title: "Paired devices", loader: Discovery.pairedBluetoothDevices) { choice in
                    step.primary = choice.value
                    step.secondary = choice.label
                }
            }
            if !step.secondary.isEmpty {
                Text("Device: \(step.secondary)").font(.caption)
            }

        case .audioOutput:
            HStack {
                TextField("Output device name, e.g. JBL Flip 5", text: $step.primary)
                ChoiceMenu(title: "Outputs", loader: Discovery.audioOutputs) { step.primary = $0.value }
            }

        case .setVolume:
            HStack {
                Slider(value: $step.amount, in: 0...100, step: 1)
                    .frame(maxWidth: 260)
                Text("\(Int(step.amount))%").monospacedDigit()
            }

        case .runShortcut:
            HStack {
                TextField("Shortcut name", text: $step.primary)
                ChoiceMenu(title: "Shortcuts", loader: Discovery.shortcuts) { step.primary = $0.value }
            }

        case .runShell:
            TextField("Command", text: $step.primary, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .monospaced))

        case .wait:
            Stepper("\(Int(step.amount)) seconds", value: $step.amount, in: 0...300, step: 1)
        }
    }
}

/// A menu whose items are fetched asynchronously when it appears (e.g. paired Bluetooth devices).
struct ChoiceMenu: View {
    let title: String
    let loader: () async -> [Choice]
    let onPick: (Choice) -> Void

    @State private var choices: [Choice] = []
    @State private var loaded = false

    var body: some View {
        Menu(title) {
            if choices.isEmpty {
                Text(loaded ? "Nothing found" : "Loading…")
            }
            ForEach(choices) { choice in
                Button(choice.label) { onPick(choice) }
            }
            Divider()
            Button("Refresh") { Task { await reload() } }
        }
        .fixedSize()
        .task { await reload() }
    }

    private func reload() async {
        choices = await loader()
        loaded = true
    }
}

struct LogView: View {
    @EnvironmentObject private var runner: Runner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if runner.log.isEmpty {
                    Text("Run a workflow to see results here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(runner.log) { line in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: line.level))
                            .foregroundStyle(color(for: line.level))
                        Text(line.text)
                    }
                }
            }
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 130)
        .background(Color.secondary.opacity(0.1))
    }

    private func icon(for level: LogLine.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .info: .secondary
        case .ok: .green
        case .failed: .red
        }
    }
}

private func chooseAppName() -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.deletingPathExtension().lastPathComponent
}
