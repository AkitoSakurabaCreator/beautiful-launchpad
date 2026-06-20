import SwiftUI

/// A single app tile: icon image plus label. The icon shape follows the chosen
/// layout style (Classic = native icon, Android = circular, Windows = square tile).
struct AppIconView: View {
    @EnvironmentObject var store: LaunchpadStore
    let app: AppInfo
    let iconSize: CGFloat
    var highlight: Bool = false
    var showLabel: Bool = true

    private var style: LayoutStyle { store.settings.layoutStyle }
    private var corner: CGFloat {
        switch style {
        case .classic: return iconSize * 0.24
        case .android: return iconSize * 0.5     // circle
        case .windows: return iconSize * 0.12    // rounded square tile
        case .cyber:   return iconSize * 0.16    // neon tile
        }
    }
    private var labelColor: Color { style == .cyber ? CyberPalette.text : .white }

    var body: some View {
        VStack(spacing: style == .android ? 8 : 7) {
            ZStack {
                if highlight {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke((style == .cyber ? CyberPalette.neon : Color.white).opacity(0.9), lineWidth: 3)
                        .frame(width: iconSize + 14, height: iconSize + 14)
                }
                iconImage
            }
            if showLabel {
                Text(app.name)
                    .font(.system(size: 12.5, weight: (style == .android || style == .cyber) ? .medium : .regular))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: iconSize + 26)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconImage: some View {
        switch style {
        case .classic:
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        case .android:
            // Circular icons (icon fills a circle).
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: iconSize, height: iconSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        case .windows:
            // Square "tile": a tinted rounded square with the icon inset, so the tile
            // frame is clearly visible around every app.
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.1, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
            }
            .frame(width: iconSize, height: iconSize)
            .overlay(
                RoundedRectangle(cornerRadius: iconSize * 0.1, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        case .cyber:
            // Neon tile: dark glass square, cyan border + glow, icon inset.
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.16, style: .continuous)
                    .fill(CyberPalette.tile.opacity(0.6))
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize * 0.66, height: iconSize * 0.66)
            }
            .frame(width: iconSize, height: iconSize)
            .overlay(
                RoundedRectangle(cornerRadius: iconSize * 0.16, style: .continuous)
                    .stroke(CyberPalette.neon.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: CyberPalette.neon.opacity(0.55), radius: 8)
        }
    }
}

/// A folder tile showing a 3×3 mini preview of its first apps, plus the folder name.
struct FolderIconView: View {
    @EnvironmentObject var store: LaunchpadStore
    let folder: Folder
    let iconSize: CGFloat
    var highlight: Bool = false
    var showLabel: Bool = true

    /// Folder container corner follows the layout style (Classic rounded-rect,
    /// Android circle, Windows squarer tile) so switching layout is clearly visible.
    private func corner(_ mainCell: CGFloat) -> CGFloat {
        switch store.settings.layoutStyle {
        case .classic: return mainCell * 0.24
        case .android: return mainCell * 0.5
        case .windows: return mainCell * 0.10
        case .cyber:   return mainCell * 0.12
        }
    }

    var body: some View {
        // Up to 9 child ids for the mini preview; a child may be an app or a
        // nested folder (shown as a small tinted tile rather than an icon).
        let mini = Array(folder.appIds.prefix(9))
        let pad = iconSize * 0.13
        let gap = iconSize * 0.06
        let mainCell = iconSize * 0.92
        let rad = corner(mainCell)

        // Cyber style: dark glass fill + neon accent border + glow (the folder's own
        // colour, if set, becomes the neon accent; else default cyan).
        let isCyber = store.settings.layoutStyle == .cyber
        let accent = folder.colorHex.map { Color(hex: $0) } ?? CyberPalette.neon
        let fillColor = isCyber ? CyberPalette.tile.opacity(0.6)
            : (folder.colorHex.map { Color(hex: $0).opacity(0.55) } ?? Color.white.opacity(0.16))
        let strokeColor = isCyber ? accent.opacity(0.9) : Color.white.opacity(highlight ? 0.9 : 0.18)
        let strokeW: CGFloat = isCyber ? 1.5 : (highlight ? 3 : 1)

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: rad, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: rad, style: .continuous)
                            .stroke(strokeColor, lineWidth: strokeW)
                    )
                    .shadow(color: isCyber ? accent.opacity(0.5) : .clear, radius: isCyber ? 8 : 0)
                    .frame(width: mainCell, height: mainCell)

                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { c in
                                let idx = r * 3 + c
                                if idx < mini.count {
                                    let cid = mini[idx]
                                    if let app = store.app(cid) {
                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fit)
                                    } else if store.isFolder(cid) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Color.white.opacity(0.35))
                                            .aspectRatio(1, contentMode: .fit)
                                    } else {
                                        Color.clear
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
                .frame(width: mainCell - pad * 2, height: mainCell - pad * 2)
            }
            .frame(width: iconSize, height: iconSize)

            if showLabel {
                Text(folder.name)
                    .font(.system(size: 12.5))
                    .foregroundColor(isCyber ? CyberPalette.text : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: iconSize + 26)
            }
        }
        .contentShape(Rectangle())
    }
}
