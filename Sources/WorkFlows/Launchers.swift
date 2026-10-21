import Foundation

/// Spotlight can't run menu bar items, but it launches apps. For every workflow we keep a tiny
/// launcher app (named after the workflow) in ~/Applications/WorkFlows; opening it asks the main
/// app to run that workflow through the `workflows://run/<id>` URL.
enum Launchers {
    static let urlScheme = "workflows"
    static let appBundleID = "local.workflows.app"

    private static let bundlePrefix = "local.workflows.launcher."

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/WorkFlows", isDirectory: true)
    }

    /// Resolves `workflows://run/<id or name>` to a workflow.
    static func workflow(for url: URL, in workflows: [Workflow]) -> Workflow? {
        guard url.scheme == urlScheme, url.host == "run" else { return nil }
        let target = url.lastPathComponent
        return workflows.first { $0.id.uuidString == target }
            ?? workflows.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    /// Creates or renames a launcher per workflow and removes the ones whose workflow is gone.
    /// Only touches bundles carrying our identifier prefix.
    static func sync(_ workflows: [Workflow]) {
        let fm = FileManager.default
        let dir = directory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var wanted: [String: Workflow] = [:]   // app file name -> workflow
        for workflow in workflows {
            var base = workflow.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { base = "Workflow" }
            if wanted["\(base).app"] != nil { base += " (\(workflow.id.uuidString.prefix(4)))" }
            wanted["\(base).app"] = workflow
        }

        var changed = false
        let existing = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.pathExtension == "app" && isLauncher(url) {
            let keep = wanted[url.lastPathComponent].map { installedID(at: url) == $0.id.uuidString } ?? false
            if !keep {
                try? fm.removeItem(at: url)
                changed = true
            }
        }
        for (fileName, workflow) in wanted {
            let url = dir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: url.path) { continue }
            if write(workflow, named: String(fileName.dropLast(4)), to: url) { changed = true }
        }

        if changed {
            // Nudge Spotlight so new launchers show up without waiting for the next index pass.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
            process.arguments = [dir.path]
            try? process.run()
        }
    }

    private static func isLauncher(_ app: URL) -> Bool {
        installedID(at: app) != nil
    }

    private static func installedID(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist),
              let id = dict["CFBundleIdentifier"] as? String,
              id.hasPrefix(bundlePrefix) else { return nil }
        return String(id.dropFirst(bundlePrefix.count))
    }

    private static func write(_ workflow: Workflow, named name: String, to app: URL) -> Bool {
        let fm = FileManager.default
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let id = workflow.id.uuidString
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key><string>\(xmlEscape(name))</string>
            <key>CFBundleDisplayName</key><string>\(xmlEscape(name))</string>
            <key>CFBundleIdentifier</key><string>\(bundlePrefix)\(id)</string>
            <key>CFBundleExecutable</key><string>launch</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleVersion</key><string>1</string>
            <key>LSUIElement</key><true/>
        </dict>
        </plist>
        """
        let script = """
        #!/bin/sh
        exec /usr/bin/open -b \(appBundleID) "\(urlScheme)://run/\(id)"
        """

        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
            let exe = macOS.appendingPathComponent("launch")
            try script.write(to: exe, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        } catch {
            try? fm.removeItem(at: app)
            return false
        }

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", app.path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        try? sign.run()
        sign.waitUntilExit()
        return true
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
