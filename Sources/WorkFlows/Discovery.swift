import Foundation

/// Helpers that ask the system what's available, to populate the pickers in the editor.
enum Discovery {
    static func pairedBluetoothDevices() async -> [Choice] {
        let json = await Shell.tool("blueutil", ["--paired", "--format", "json"])
        if json.ok,
           let data = json.output.data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return items.compactMap { item in
                guard let address = item["address"] as? String else { return nil }
                return Choice(label: (item["name"] as? String) ?? address, value: address)
            }
        }

        // Older blueutil without --format: lines like
        //   address: aa-bb-cc, not connected, not favourite, paired, name: "Foo", recent access date: ...
        let plain = await Shell.tool("blueutil", ["--paired"])
        guard plain.ok else { return [] }
        return plain.output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: ", ")
            guard let addressPart = parts.first(where: { $0.hasPrefix("address: ") }) else { return nil }
            let address = String(addressPart.dropFirst("address: ".count))
            let name = parts.first(where: { $0.hasPrefix("name: ") })
                .map { String($0.dropFirst("name: ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            return Choice(label: name ?? address, value: address)
        }
    }

    static func audioOutputs() async -> [Choice] {
        let result = await Shell.tool("SwitchAudioSource", ["-a", "-t", "output"])
        guard result.ok else { return [] }
        return result.output.split(separator: "\n").compactMap { line in
            // Output may be "Name" or "Name (output)" depending on version; strip the suffix.
            var name = String(line).trimmingCharacters(in: .whitespaces)
            for suffix in [" (output)", " (input)", " (system)"] where name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
            return name.isEmpty ? nil : Choice(label: name, value: name)
        }
    }

    static func shortcuts() async -> [Choice] {
        let result = await Shell.run("/usr/bin/shortcuts", ["list"])
        guard result.ok else { return [] }
        return result.output.split(separator: "\n").map { Choice(label: String($0), value: String($0)) }
    }
}

enum Browser {
    static let known = ["Google Chrome", "Microsoft Edge", "Safari", "Firefox", "Arc", "Brave Browser", "Vivaldi", "Opera"]

    /// Installed browsers from the known list, plus whatever is currently selected.
    static func options(including current: String) -> [String] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var result = known.filter { name in
            name == "Safari" || dirs.contains { fm.fileExists(atPath: "\($0)/\(name).app") }
        }
        if !current.isEmpty && !result.contains(current) { result.append(current) }
        return result
    }
}
