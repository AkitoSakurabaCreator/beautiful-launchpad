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
    ]

    static func preset(_ index: Int) -> ThemePreset {
        themes[min(max(0, index), themes.count - 1)]
    }

    static func gradient(_ index: Int) -> LinearGradient {
        let t = preset(index)
        return LinearGradient(colors: t.colors, startPoint: t.start, endPoint: t.end)
    }
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

/// Full-screen background, driven by the user's appearance settings.
struct BackgroundView: View {
    let settings: AppSettings

    var body: some View {
        ZStack {
            switch settings.backgroundKind {
            case .desktopBlur:
                VisualEffectView().ignoresSafeArea()
            case .theme:
                Theming.gradient(settings.themeIndex).ignoresSafeArea()
            case .solid:
                Color(hex: settings.solidColorHex).ignoresSafeArea()
            case .image:
                if let path = settings.wallpaperPath,
                   let img = NSImage(contentsOfFile: path) {
                    // A fill-image MUST be pinned to an exact size. Otherwise the
                    // overflow inflates the parent ZStack and pushes the Spacer-
                    // positioned gear button off the top-right of the screen.
                    // GeometryReader yields the exact container size; framing the
                    // image to it + clipping guarantees it is never larger.
                    GeometryReader { geo in
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .ignoresSafeArea()
                } else {
                    Theming.gradient(settings.themeIndex).ignoresSafeArea()
                }
            }
            Color.black.opacity(settings.dim).ignoresSafeArea()
        }
    }
}
