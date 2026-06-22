import SwiftUI
import AppKit

/// A named gradient background preset.
struct ThemePreset: Identifiable {
    let id: Int
    let name: String
    let colors: [Color]
    let start: UnitPoint
    let end: UnitPoint
}

enum Theming {
    static let themes: [ThemePreset] = [
        ThemePreset(id: 0, name: "Midnight",
                    colors: [Color(hex: "#1A1340"), Color(hex: "#0B1026"), Color(hex: "#060814")],
                    start: .topLeading, end: .bottomTrailing),
        ThemePreset(id: 1, name: "Aurora",
                    colors: [Color(hex: "#7C3AED"), Color(hex: "#2563EB"), Color(hex: "#0891B2")],
                    start: .topLeading, end: .bottomTrailing),
        ThemePreset(id: 2, name: "Sunset",
                    colors: [Color(hex: "#F59E0B"), Color(hex: "#DB2777"), Color(hex: "#7C3AED")],
                    start: .top, end: .bottom),
        ThemePreset(id: 3, name: "Forest",
                    colors: [Color(hex: "#064E3B"), Color(hex: "#065F46"), Color(hex: "#0B1026")],
                    start: .topLeading, end: .bottomTrailing),
        ThemePreset(id: 4, name: "Graphite",
                    colors: [Color(hex: "#2B2B2E"), Color(hex: "#1A1A1C"), Color(hex: "#0E0E10")],
                    start: .top, end: .bottom),
        ThemePreset(id: 5, name: "Rose",
                    colors: [Color(hex: "#9D174D"), Color(hex: "#7C3AED"), Color(hex: "#1E1B4B")],
                    start: .topLeading, end: .bottomTrailing),
        // Neon cyberpunk: cyan → violet → hot-pink over a near-black base.
        ThemePreset(id: 6, name: "Cyber",
                    colors: [Color(hex: "#00F0FF"), Color(hex: "#7A2BFF"),
                             Color(hex: "#FF2D95"), Color(hex: "#070217")],
                    start: .topLeading, end: .bottomTrailing),
        // Frosted glass: cool pale cyan → frosty white → soft lavender.
        ThemePreset(id: 7, name: "Glass",
                    colors: [Color(hex: "#8FB8D6"), Color(hex: "#DCEAF2"), Color(hex: "#B7C4E8")],
                    start: .topLeading, end: .bottomTrailing),
    ]

    static func preset(_ index: Int) -> ThemePreset {
        themes[min(max(0, index), themes.count - 1)]
    }

    static func gradient(_ index: Int) -> LinearGradient {
        let t = preset(index)
        return LinearGradient(colors: t.colors, startPoint: t.start, endPoint: t.end)
    }
}

/// Neon accent palette for the Cyber layout style (icons / folders / widgets).
enum CyberPalette {
    static let neon = Color(hex: "#00F0FF")   // cyan
    static let neon2 = Color(hex: "#FF2D95")  // hot pink
    static let text = Color(hex: "#7DF9FF")   // light cyan label
    static let tile = Color(hex: "#0B0A1F")   // dark glass base
}

extension Color {
    /// Create a Color from a "#RRGGBB" string.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self = Color(
                red: Double((v & 0xFF0000) >> 16) / 255,
                green: Double((v & 0x00FF00) >> 8) / 255,
                blue: Double(v & 0x0000FF) / 255
            )
        } else {
            self = Color.black
        }
    }

    /// Convert to a "#RRGGBB" string (sRGB).
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Full-screen background, driven by the user's appearance settings. When a per-page
/// override exists for `pageIndex` it takes precedence over the global background.
struct BackgroundView: View {
    let settings: AppSettings
    /// Page currently shown (for per-page overrides). `nil` = use the global background
    /// (e.g. while searching or with a folder open).
    var pageIndex: Int? = nil
    /// When true, AppKit owns video playback below the SwiftUI host. SwiftUI still
    /// draws dim/page overrides, but it does not embed its own AVPlayerLayer.
    var videoHandledExternally: Bool = false

    /// The per-page override for the current page, if any.
    private var pageOverride: PageBackground? {
        guard let p = pageIndex else { return nil }
        return settings.pageBackgrounds["\(p)"]
    }

    var body: some View {
        ZStack {
            if let pb = pageOverride {
                pageOverrideView(pb)
            } else {
                globalBackground
            }
            Color.black.opacity(settings.dim).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func pageOverrideView(_ pb: PageBackground) -> some View {
        switch pb.kind {
        case .color:
            Color(hex: pb.colorHex ?? "#000000").ignoresSafeArea()
        case .image:
            if let path = pb.imagePath, let img = NSImage(contentsOfFile: path) {
                fillImage(img)
            } else {
                globalBackground
            }
        case .video:
            // Per-page video is always hosted inside SwiftUI (it follows the paged
            // grid). The external AppKit video window only backs the *global* video
            // background; here the page override draws above it. Mute/volume reuse
            // the global video settings for simplicity.
            if let path = pb.videoPath, FileManager.default.fileExists(atPath: path) {
                VideoBackgroundView(paths: [path],
                                    muted: settings.videoMuted,
                                    volume: settings.videoVolume)
                    .id("pagevideo:\(path)")
                    .ignoresSafeArea()
            } else {
                globalBackground
            }
        case .slideshow:
            if let folder = pb.slideshowFolder {
                SlideshowBackgroundView(folder: folder,
                                        interval: settings.slideshowInterval,
                                        random: settings.slideshowRandom,
                                        animated: settings.animationsEnabled)
                    .id("pageslideshow:\(folder)")
                    .ignoresSafeArea()
            } else {
                globalBackground
            }
        }
    }

    @ViewBuilder
    private var globalBackground: some View {
        switch settings.backgroundKind {
        case .desktopBlur:
            // The borderless window is transparent, so the real desktop shows through
            // crisply. A frosted-glass overlay is cross-faded over it by `blurIntensity`
            // (0 = no blur / crisp desktop, 1 = full frosted glass).
            ZStack {
                Color.clear
                VisualEffectView(material: .hudWindow)
                    .opacity(settings.blurIntensity)
            }
            .ignoresSafeArea()
        case .theme:
            Theming.gradient(settings.themeIndex).ignoresSafeArea()
        case .solid:
            Color(hex: settings.solidColorHex).ignoresSafeArea()
        case .image:
            if let path = settings.wallpaperPath, let img = NSImage(contentsOfFile: path) {
                // `.id(path)` forces a fresh view when the chosen image changes.
                fillImage(img).id(path)
            } else {
                Theming.gradient(settings.themeIndex).ignoresSafeArea()
            }
        case .slideshow:
            if let folder = settings.slideshowFolder {
                SlideshowBackgroundView(folder: folder,
                                        interval: settings.slideshowInterval,
                                        random: settings.slideshowRandom,
                                        animated: settings.animationsEnabled)
                    // Recreate when the folder changes so a newly picked folder loads
                    // immediately (preserved @State otherwise kept the old images).
                    .id(folder)
                    .ignoresSafeArea()
            } else {
                Theming.gradient(settings.themeIndex).ignoresSafeArea()
            }
        case .video:
            if videoHandledExternally {
                Color.clear.ignoresSafeArea()
            } else if let folder = settings.videoFolder {
                // Folder playlist (ordered / shuffled).
                VideoFolderBackgroundView(folder: folder,
                                          random: settings.videoRandom,
                                          muted: settings.videoMuted,
                                          volume: settings.videoVolume,
                                          fallback: Theming.gradient(settings.themeIndex))
                    .ignoresSafeArea()
            } else if let path = settings.videoPath, FileManager.default.fileExists(atPath: path) {
                // Single looping clip. `.id(path)` swaps the player when the file
                // changes; mute/volume are applied in place so toggling keeps position.
                VideoBackgroundView(paths: [path], muted: settings.videoMuted, volume: settings.videoVolume)
                    .id("vfile:\(path)")
                    .ignoresSafeArea()
            } else {
                Theming.gradient(settings.themeIndex).ignoresSafeArea()
            }
        }
    }

    /// A fill-image MUST be pinned to an exact size; otherwise the overflow inflates
    /// the parent ZStack and pushes the Spacer-positioned gear button off-screen.
    private func fillImage(_ img: NSImage) -> some View {
        GeometryReader { geo in
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}
