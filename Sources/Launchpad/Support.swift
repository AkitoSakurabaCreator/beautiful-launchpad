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
