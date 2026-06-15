import AppKit

/// Discovers installed applications from the standard macOS application locations
/// and loads their icons, mirroring what the classic Launchpad displayed.
enum AppScanner {
    static var roots: [String] {
        [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            NSHomeDirectory() + "/Applications",
        ]
    }

    static func scan() -> [AppInfo] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [AppInfo] = []

        func consider(_ url: URL) {
            guard url.pathExtension == "app" else { return }
            let path = url.path
            guard !seen.contains(path) else { return }
            // Must be a real, launchable bundle.
            guard fm.fileExists(atPath: path) else { return }
            seen.insert(path)

            var name = fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }

            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 128, height: 128)

            result.append(AppInfo(id: path, name: name, url: url, icon: icon))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard
                let items = try? fm.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }

            for item in items {
                if item.pathExtension == "app" {
                    consider(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // Descend one level for grouped suites (e.g. Microsoft Office, Adobe …).
                    if let sub = try? fm.contentsOfDirectory(
                        at: item,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) {
                        for child in sub where child.pathExtension == "app" {
                            consider(child)
                        }
                    }
                }
            }
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }
}
