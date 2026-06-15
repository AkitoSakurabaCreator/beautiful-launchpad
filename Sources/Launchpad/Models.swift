import AppKit

/// A discovered installed application. `id` is the file-system path (stable per machine).
struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let icon: NSImage

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What a user-added custom item launches.
enum CustomItemKind: String, Codable, CaseIterable {
    case app     // an .app bundle (or any path) at an arbitrary location
    case script  // a script file or a shell command line
    case url     // a web URL / deep link opened in the default handler
}

/// A user-created launcher entry that is NOT discovered by the app scanner.
/// Persisted in the layout so it survives rescans, and synthesised into the
/// catalogue as an `AppInfo` so the existing grid / folder / drag machinery works.
/// `id` is `"custom-<uuid>"`.
struct CustomItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var kind: CustomItemKind
    /// app: file path · script: shell-quoted path or a command line · url: URL string.
    var target: String
    /// Optional override icon image, or a file to derive an icon from.
    var iconPath: String? = nil
}

/// A user-created folder grouping several apps.
struct Folder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var appIds: [String]
    /// Optional tint (hex like `#RRGGBB`). `nil` = default translucent white.
    var colorHex: String? = nil
}

/// On-disk layout persisted to Application Support so the arrangement survives relaunch.
struct PersistedLayout: Codable {
    /// Ordered top-level ids; each is an app path, a `custom-…` id, or a `folder-…` id.
    var order: [String]
    var folders: [Folder]
    /// User-added entries (apps/scripts/URLs at arbitrary locations).
    var customItems: [CustomItem]

    init(order: [String], folders: [Folder], customItems: [CustomItem] = []) {
        self.order = order
        self.folders = folders
        self.customItems = customItems
    }

    enum CodingKeys: String, CodingKey { case order, folders, customItems }

    // Tolerate older files that predate `customItems` (and partial/hand-edited JSON):
    // every field falls back to a safe default rather than failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        folders = (try? c.decode([Folder].self, forKey: .folders)) ?? []
        customItems = (try? c.decode([CustomItem].self, forKey: .customItems)) ?? []
    }
}

/// How the full-screen background is drawn.
enum BackgroundKind: String, Codable, CaseIterable {
    case desktopBlur   // frosted real desktop (classic look)
    case theme         // built-in gradient preset
    case solid         // single colour
    case image         // user-picked wallpaper image
}

/// User-customisable appearance settings.
struct AppSettings: Codable {
    var backgroundKind: BackgroundKind = .desktopBlur
    var themeIndex: Int = 1
    var solidColorHex: String = "#0B1026"
    var wallpaperPath: String? = nil
    var columns: Int = 7
    var rows: Int = 5
    var dim: Double = 0.22
    var showLabels: Bool = true
    var language: AppLanguage = .system

    // Tolerate older/partial files: every field has a default.
    enum CodingKeys: String, CodingKey {
        case backgroundKind, themeIndex, solidColorHex, wallpaperPath, columns, rows, dim, showLabels, language
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundKind = (try? c.decode(BackgroundKind.self, forKey: .backgroundKind)) ?? .desktopBlur
        themeIndex = (try? c.decode(Int.self, forKey: .themeIndex)) ?? 1
        solidColorHex = (try? c.decode(String.self, forKey: .solidColorHex)) ?? "#0B1026"
        wallpaperPath = try? c.decodeIfPresent(String.self, forKey: .wallpaperPath)
        columns = (try? c.decode(Int.self, forKey: .columns)) ?? 7
        rows = (try? c.decode(Int.self, forKey: .rows)) ?? 5
        dim = (try? c.decode(Double.self, forKey: .dim)) ?? 0.22
        showLabels = (try? c.decode(Bool.self, forKey: .showLabels)) ?? true
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? .system
    }

    /// Clamp every field that feeds grid math (division/modulo) or array indexing
    /// into a known-safe range. This is the single normalization point applied
    /// after any *untrusted* value enters: decode of the on-disk settings file,
    /// import of an external config bundle, and in-app mutation.
    ///
    /// Custom `init(from:)` only falls back to defaults when a key is *missing* or
    /// type-mismatched — an explicit malformed value such as `"columns": 0`
    /// decodes successfully and would otherwise reach `index % columns` /
    /// `index / columns` in `GridGeometry`, causing a divide-by-zero crash (DoS
    /// via a hand-edited or imported settings file). Normalizing here closes that.
    func normalized() -> AppSettings {
        var s = self
        s.columns = min(max(s.columns, 4), 10)
        s.rows = min(max(s.rows, 3), 8)
        s.dim = min(max(s.dim, 0), 1)
        s.themeIndex = min(max(s.themeIndex, 0), Theming.themes.count - 1)
        return s
    }
}

/// Combined, portable export bundle (layout + appearance) for moving between Macs.
struct ExportBundle: Codable {
    var version: Int = 1
    var layout: PersistedLayout
    var settings: AppSettings
}
