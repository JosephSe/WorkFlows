import Foundation
import ServiceManagement

/// Workflows persisted as JSON at ~/Library/Application Support/WorkFlows/workflows.json
@MainActor
final class Store: ObservableObject {
    @Published var workflows: [Workflow] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFlows", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("workflows.json")
        fileURL = url

        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode([Workflow].self, from: data) {
                workflows = decoded
            } else {
                // Unreadable file: keep a copy before the defaults overwrite it.
                try? data.write(to: url.appendingPathExtension("bak"))
                workflows = Workflow.defaults
            }
        } else {
            workflows = Workflow.defaults
        }

        // "Stop Work" shipped after the first release: add it once to existing installs, never again,
        // so deleting it sticks.
        let flag = "seededStopWork"
        if !UserDefaults.standard.bool(forKey: flag) {
            UserDefaults.standard.set(true, forKey: flag)
            if !workflows.contains(where: { $0.name == Workflow.stopWork.name }) {
                workflows.append(Workflow.stopWork)
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(workflows) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
