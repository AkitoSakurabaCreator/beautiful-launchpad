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
    case app          // an .app bundle (or any path) at an arbitrary location
    case script       // a script file or a shell command line
    case url          // a web URL / deep link opened in the default handler
    case randomImage  // open a random image from a folder (`target` = folder path)
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

/// Kinds of widget tiles the user can place on the grid (free-positioned & resizable).
enum WidgetKind: String, Codable, CaseIterable {
    case clock     // live digital clock
    case date      // current date + weekday
    case notes     // editable sticky note
    case battery   // battery percentage / charging
    case system    // memory usage + uptime
    case weather   // current conditions (network)
    case image     // user-picked still image (`text` = file path)
    case video     // user-picked looping video (`text` = file path)
}

/// A user-placed widget. Position/size are normalized (0…1) within the page area so
/// they survive window/display size changes. `id` is `"widget-<uuid>"`.
struct WidgetItem: Identifiable, Codable, Hashable {
    var id: String
    var kind: WidgetKind
    var page: Int = 0
    var x: Double = 0.5       // normalized centre
    var y: Double = 0.5
    var w: Double = 0.22      // normalized size
    var h: Double = 0.16
    var text: String = ""     // notes content · image/video file path · per-widget config
    /// Hide the card background/border (for transparent images, alpha videos, overlays).
    var transparent: Bool = false
    /// Video widget: mute its audio (default on).
    var muted: Bool = true
    /// Video widget: audio volume 0…1 (used when not muted).
    var volume: Double = 0.6
    /// Content opacity 0…1 (how transparent the image/video is drawn). 1 = opaque.
    var opacity: Double = 1.0
    /// Rotation in degrees (−180…180).
    var rotation: Double = 0
    /// When locked: no hover UI, no drag/resize. Unlock via right-click menu.
    var locked: Bool = false

    /// Clamp every field into a safe range (defends against hand-edited files).
    func normalized() -> WidgetItem {
        var v = self
        v.page = min(max(v.page, 0), 63)
        v.x = min(max(v.x, 0), 1)
        v.y = min(max(v.y, 0), 1)
        v.w = min(max(v.w, 0.08), 0.9)
        v.h = min(max(v.h, 0.06), 0.9)
        v.volume = min(max(v.volume, 0), 1)
        v.opacity = min(max(v.opacity, 0.05), 1)
        v.rotation = min(max(v.rotation, -180), 180)
        return v
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, page, x, y, w, h, text, transparent, muted, volume, opacity, rotation, locked
    }
}

extension WidgetItem {
    // Decode-tolerant: tolerate files that predate newer fields so a single older
    // widget can't wipe the whole array.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(WidgetKind.self, forKey: .kind)) ?? .clock
        page = (try? c.decode(Int.self, forKey: .page)) ?? 0
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0.5
        w = (try? c.decode(Double.self, forKey: .w)) ?? 0.22
        h = (try? c.decode(Double.self, forKey: .h)) ?? 0.16
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        transparent = (try? c.decode(Bool.self, forKey: .transparent)) ?? false
        muted = (try? c.decode(Bool.self, forKey: .muted)) ?? true
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? 0.6
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 1.0
        rotation = (try? c.decode(Double.self, forKey: .rotation)) ?? 0
        locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
    }
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
    /// Ids the user chose to hide. Kept here (not just dropped) so a hidden app is
    /// not re-added on the next scan, and can be restored from Settings.
    var hidden: [String]
    /// Free-placement coordinates (normalized 0…1 within the page area), keyed by
    /// top-level id. Used only when AppSettings.freePlacement is on; empty = auto-grid.
    var freePositions: [String: CGPoint]
    /// Free-placement page assignment per id (which page the item sits on). Lets the
    /// user spread items across pages in free mode independent of `order`.
    var freePages: [String: Int]
    /// User-placed widgets (free-positioned & resizable).
    var widgets: [WidgetItem]

    init(order: [String], folders: [Folder], customItems: [CustomItem] = [],
         hidden: [String] = [], freePositions: [String: CGPoint] = [:], freePages: [String: Int] = [:],
         widgets: [WidgetItem] = []) {
        self.order = order
        self.folders = folders
        self.customItems = customItems
        self.hidden = hidden
        self.freePositions = freePositions
        self.freePages = freePages
        self.widgets = widgets
    }

    enum CodingKeys: String, CodingKey {
        case order, folders, customItems, hidden, freePositions, freePages, widgets
    }

    // Tolerate older files that predate newer fields (and partial/hand-edited JSON):
    // every field falls back to a safe default rather than failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode([String].self, forKey: .order)) ?? []
        folders = (try? c.decode([Folder].self, forKey: .folders)) ?? []
        customItems = (try? c.decode([CustomItem].self, forKey: .customItems)) ?? []
        hidden = (try? c.decode([String].self, forKey: .hidden)) ?? []
        freePositions = (try? c.decode([String: CGPoint].self, forKey: .freePositions)) ?? [:]
        freePages = (try? c.decode([String: Int].self, forKey: .freePages)) ?? [:]
        widgets = (try? c.decode([WidgetItem].self, forKey: .widgets)) ?? []
    }
}

/// How the full-screen background is drawn.
enum BackgroundKind: String, Codable, CaseIterable {
    case desktopBlur   // frosted real desktop (classic look)
    case theme         // built-in gradient preset
    case solid         // single colour
    case image         // user-picked wallpaper image
    case slideshow     // cycle through images in a folder
    case video         // looping muted video file
}

/// Open/close transition style for the Launchpad overlay.
enum OpenAnimation: String, Codable, CaseIterable {
    case zoom    // classic Launchpad fade + scale
    case fade    // opacity only
    case slide   // slide up from the bottom
    case none    // instant (no transition)
}

/// Overall layout personality. The classic 7×5 paged grid plus themed variants that
/// restyle icon shape, label, density, and accent to evoke other desktops.
enum LayoutStyle: String, Codable, CaseIterable {
    case classic   // macOS Launchpad
    case android   // rounded/larger icons, label-forward
    case windows   // tile-like square icons, denser grid
    case cyber     // neon-bordered glowing tiles, dark glass folders, cyan labels
}

/// A per-page background override (used when the user customises individual pages).
struct PageBackground: Codable, Hashable {
    enum Kind: String, Codable { case color, image }
    var kind: Kind
    var colorHex: String?
    var imagePath: String?
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

    /// Desktop-blur intensity, 0…1. 0 = no blur (crisp desktop), 1 = full frosted glass.
    /// Implemented by cross-fading a frosted overlay over the crisp desktop.
    var blurIntensity: Double = 0.6
    /// Folder overlay grid dimensions (drives the open-folder card size & per-page capacity).
    var folderColumns: Int = 5
    var folderRows: Int = 4
    /// Play a short sound when an app/item is launched.
    var launchSound: Bool = false
    /// System sound name used for the launch sound (e.g. "Pop", "Tink").
    var launchSoundName: String = "Pop"
    /// Optional custom sound file for the launch sound; overrides `launchSoundName`.
    var launchSoundPath: String? = nil
    /// Mute the looping video background (off = play its audio).
    var videoMuted: Bool = true
    /// Video background audio volume (0…1), used when not muted.
    var videoVolume: Double = 0.6

    // Animation
    var animationsEnabled: Bool = true
    /// Multiplier: 0.5 = slow … 2.0 = fast (durations are divided by this).
    var animationSpeed: Double = 1.0
    var openAnimation: OpenAnimation = .zoom

    // Layout / placement
    var freePlacement: Bool = false
    var layoutStyle: LayoutStyle = .classic

    // Video / slideshow backgrounds
    var videoPath: String? = nil
    /// Optional folder of videos played as a playlist (overrides `videoPath`).
    var videoFolder: String? = nil
    /// Shuffle the video playlist (vs. sequential). Only relevant with `videoFolder`.
    var videoRandom: Bool = true
    var slideshowFolder: String? = nil
    var slideshowInterval: Double = 30          // seconds between images
    var slideshowRandom: Bool = true

    /// Per-page background overrides, keyed by page index as a string ("0", "1", …).
    var pageBackgrounds: [String: PageBackground] = [:]

    /// First-run onboarding / permission dialog has been shown.
    var onboardingShown: Bool = false

    // Tolerate older/partial files: every field has a default.
    enum CodingKeys: String, CodingKey {
        case backgroundKind, themeIndex, solidColorHex, wallpaperPath, columns, rows, dim, showLabels, language
        case blurIntensity, folderColumns, folderRows, launchSound, launchSoundName, launchSoundPath, videoMuted, videoVolume
        case animationsEnabled, animationSpeed, openAnimation, freePlacement, layoutStyle
        case videoPath, videoFolder, videoRandom, slideshowFolder, slideshowInterval, slideshowRandom, pageBackgrounds, onboardingShown
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
        blurIntensity = (try? c.decode(Double.self, forKey: .blurIntensity)) ?? 0.6
        folderColumns = (try? c.decode(Int.self, forKey: .folderColumns)) ?? 5
        folderRows = (try? c.decode(Int.self, forKey: .folderRows)) ?? 4
        launchSound = (try? c.decode(Bool.self, forKey: .launchSound)) ?? false
        launchSoundName = (try? c.decode(String.self, forKey: .launchSoundName)) ?? "Pop"
        launchSoundPath = try? c.decodeIfPresent(String.self, forKey: .launchSoundPath)
        videoMuted = (try? c.decode(Bool.self, forKey: .videoMuted)) ?? true
        videoVolume = (try? c.decode(Double.self, forKey: .videoVolume)) ?? 0.6
        animationsEnabled = (try? c.decode(Bool.self, forKey: .animationsEnabled)) ?? true
        animationSpeed = (try? c.decode(Double.self, forKey: .animationSpeed)) ?? 1.0
        openAnimation = (try? c.decode(OpenAnimation.self, forKey: .openAnimation)) ?? .zoom
        freePlacement = (try? c.decode(Bool.self, forKey: .freePlacement)) ?? false
        layoutStyle = (try? c.decode(LayoutStyle.self, forKey: .layoutStyle)) ?? .classic
        videoPath = try? c.decodeIfPresent(String.self, forKey: .videoPath)
        videoFolder = try? c.decodeIfPresent(String.self, forKey: .videoFolder)
        videoRandom = (try? c.decode(Bool.self, forKey: .videoRandom)) ?? true
        slideshowFolder = try? c.decodeIfPresent(String.self, forKey: .slideshowFolder)
        slideshowInterval = (try? c.decode(Double.self, forKey: .slideshowInterval)) ?? 30
        slideshowRandom = (try? c.decode(Bool.self, forKey: .slideshowRandom)) ?? true
        pageBackgrounds = (try? c.decode([String: PageBackground].self, forKey: .pageBackgrounds)) ?? [:]
        onboardingShown = (try? c.decode(Bool.self, forKey: .onboardingShown)) ?? false
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
        s.blurIntensity = min(max(s.blurIntensity, 0), 1)
        s.videoVolume = min(max(s.videoVolume, 0), 1)
        s.folderColumns = min(max(s.folderColumns, 3), 8)
        s.folderRows = min(max(s.folderRows, 2), 6)
        s.animationSpeed = min(max(s.animationSpeed, 0.25), 3.0)
        s.slideshowInterval = min(max(s.slideshowInterval, 3), 600)
        return s
    }
}

/// Combined, portable export bundle (layout + appearance) for moving between Macs.
struct ExportBundle: Codable {
    var version: Int = 1
    var layout: PersistedLayout
    var settings: AppSettings
}
