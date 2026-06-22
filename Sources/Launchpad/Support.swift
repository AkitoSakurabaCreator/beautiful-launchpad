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

struct LiquidGlassBackground<S: InsettableShape>: View {
    let shape: S
    var tint: Color = GlassPalette.accent
    var transparency: Double = 0
    var materialOpacity: Double = 1.0
    var sheenOpacity: Double = 0.18
    var tintOpacity: Double = 0.08
    var warmOpacity: Double = 0.04
    var innerStrokeOpacity: Double = 0.12
    var strokeOpacity: Double = 0.34
    var shadowOpacity: Double = 0.22

    private func adjusted(_ base: Double, reduction: Double = 0.65) -> Double {
        GlassPalette.adjustedOpacity(base, transparency: transparency, reduction: reduction)
    }

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .opacity(adjusted(materialOpacity))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            GlassPalette.sheen.opacity(adjusted(sheenOpacity, reduction: 0.55)),
                            tint.opacity(adjusted(tintOpacity, reduction: 0.55)),
                            GlassPalette.warmEdge.opacity(adjusted(warmOpacity, reduction: 0.55)),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
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
            )
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(adjusted(innerStrokeOpacity, reduction: 0.45)), lineWidth: 0.5)
                    .blur(radius: 0.6)
            )
            .shadow(color: tint.opacity(adjusted(shadowOpacity, reduction: 0.45)), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(adjusted(0.10, reduction: 0.35)), radius: 10, x: 0, y: 6)
    }
}
