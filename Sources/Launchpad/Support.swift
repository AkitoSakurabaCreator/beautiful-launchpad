import SwiftUI
import AppKit

extension JSONEncoder {
    /// Human-readable encoder used for exported config files.
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Split an array into fixed-size chunks. Always returns at least one (possibly empty) page.
func chunk<T>(_ arr: [T], _ size: Int) -> [[T]] {
    if size <= 0 { return [arr] }
    var out: [[T]] = []
    var i = 0
    while i < arr.count {
        out.append(Array(arr[i..<min(i + size, arr.count)]))
        i += size
    }
    if out.isEmpty { out.append([]) }
    return out
}

/// Geometry describing the regular app grid for one page. Used both for layout
/// and for hit-testing during drag-and-drop (so the maths matches exactly).
struct GridGeometry {
    var columns: Int = 7
    var rows: Int = 5
    var cellWidth: CGFloat = 120
    var cellHeight: CGFloat = 120
    var hSpacing: CGFloat = 28
    var vSpacing: CGFloat = 22
    var leftPad: CGFloat = 0
    var topPad: CGFloat = 0
    var pageSize: Int { max(1, columns * rows) }

    func cellCenter(forIndex index: Int) -> CGPoint {
        // Defense in depth: never divide/mod by zero even if a bad `columns`
        // somehow reaches here (settings are normalized upstream, but this keeps
        // the geometry math total).
        let cols = max(1, columns)
        let col = index % cols
        let row = index / cols
        let x = leftPad + CGFloat(col) * (cellWidth + hSpacing) + cellWidth / 2
        let y = topPad + CGFloat(row) * (cellHeight + vSpacing) + cellHeight / 2
        return CGPoint(x: x, y: y)
    }
}

/// SwiftUI wrapper around NSVisualEffectView to get the frosted-desktop blur
/// behind the Launchpad grid (the classic Launchpad look).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = .active
    }
}

enum GlassPalette {
    static let accent = Color(hex: "#D7F7FF")
    static let sheen = Color(hex: "#FFFFFF")
    static let coolEdge = Color(hex: "#90D7FF")
    static let warmEdge = Color(hex: "#FFDDF7")

    static func adjustedOpacity(_ base: Double, transparency: Double, reduction: Double = 0.65) -> Double {
        let t = min(max(transparency, 0), 1)
        return min(max(base * (1 - t * reduction), 0), 1)
    }
}

extension AppSettings {
    var usesVideoBackground: Bool {
        guard backgroundKind == .video else { return false }
        if let folder = videoFolder, !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let path = videoPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
}

struct LiquidGlassBackground<S: InsettableShape>: View {
    let shape: S
    var tint: Color = GlassPalette.accent
    var transparency: Double = 0
    var reduceLiveBlur: Bool = false
    var materialOpacity: Double = 1.0
    var sheenOpacity: Double = 0.18
    var tintOpacity: Double = 0.08
    var warmOpacity: Double = 0.04
    var innerStrokeOpacity: Double = 0.12
    var strokeOpacity: Double = 0.34
    var shadowOpacity: Double = 0.22
    // Liquid-Glass specular lighting (generic; works on macOS 13+, no OS-26-only API).
    // All static gradients, so they add no live-blur / video-compositing cost.
    var highlightOpacity: Double = 0.46   // top sheen — light catching the upper edge
    var specularOpacity: Double = 0.22    // diagonal glossy reflection streak ("光の反射")
    var depthOpacity: Double = 0.12       // bottom inner shadow — perceived glass thickness

    private func adjusted(_ base: Double, reduction: Double = 0.65) -> Double {
        GlassPalette.adjustedOpacity(
            base,
            transparency: transparency,
            reduction: reduceLiveBlur ? max(reduction, 0.78) : reduction
        )
    }

    var body: some View {
        ZStack {
            baseLayer
            shape.fill(
                LinearGradient(
                    colors: [
                        GlassPalette.sheen.opacity(adjusted(sheenOpacity * liveBlurScale, reduction: 0.55)),
                        tint.opacity(adjusted(tintOpacity * liveBlurScale, reduction: 0.55)),
                        GlassPalette.warmEdge.opacity(adjusted(warmOpacity * liveBlurScale, reduction: 0.55)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Bottom inner shadow — gives the glass a sense of thickness/depth so it
            // reads as a lens rather than a flat translucent panel.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.58),
                        .init(color: .black.opacity(adjusted(depthOpacity, reduction: 0.5)), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Top specular sheen — light catching the upper edge of the glass.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(adjusted(highlightOpacity, reduction: 0.45)), location: 0.0),
                        .init(color: .white.opacity(adjusted(highlightOpacity * 0.20, reduction: 0.45)), location: 0.16),
                        .init(color: .clear, location: 0.46),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .blendMode(.plusLighter)
            // Diagonal glossy reflection streak — the "light reflection" highlight that
            // makes the surface read as polished glass.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: .white.opacity(adjusted(specularOpacity, reduction: 0.5)), location: 0.45),
                        .init(color: .white.opacity(adjusted(specularOpacity * 0.5, reduction: 0.5)), location: 0.51),
                        .init(color: .clear, location: 0.66),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        GlassPalette.sheen.opacity(adjusted(strokeOpacity + 0.10, reduction: 0.30)),
                        GlassPalette.coolEdge.opacity(adjusted(strokeOpacity, reduction: 0.30)),
                        GlassPalette.warmEdge.opacity(adjusted(strokeOpacity * 0.65, reduction: 0.30)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            shape
                .strokeBorder(Color.white.opacity(adjusted(innerStrokeOpacity, reduction: 0.45)), lineWidth: 0.5)
                .blur(radius: reduceLiveBlur ? 0.25 : 0.6)
        }
        .shadow(color: tint.opacity(adjusted(shadowOpacity * liveBlurScale, reduction: 0.45)),
                radius: reduceLiveBlur ? 4 : 12, x: 0, y: reduceLiveBlur ? 2 : 5)
        .shadow(color: .black.opacity(adjusted(0.10 * liveBlurScale, reduction: 0.35)),
                radius: reduceLiveBlur ? 3 : 10, x: 0, y: reduceLiveBlur ? 2 : 6)
    }

    private var liveBlurScale: Double { reduceLiveBlur ? 0.42 : 1 }

    @ViewBuilder
    private var baseLayer: some View {
        if reduceLiveBlur {
            shape.fill(
                LinearGradient(
                    colors: [
                        GlassPalette.sheen.opacity(adjusted(materialOpacity * 0.16, reduction: 0.30)),
                        tint.opacity(adjusted(materialOpacity * 0.10, reduction: 0.30)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            shape
                .fill(.ultraThinMaterial)
                .opacity(adjusted(materialOpacity))
        }
    }
}
