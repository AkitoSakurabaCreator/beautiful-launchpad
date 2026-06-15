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

/// A user-created folder grouping several apps.
struct Folder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var appIds: [String]
}

/// On-disk layout persisted to Application Support so the arrangement survives relaunch.
struct PersistedLayout: Codable {
    /// Ordered top-level ids; each is either an app path or a `folder-…` id.
    var order: [String]
    var folders: [Folder]
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
