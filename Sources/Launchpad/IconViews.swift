import SwiftUI

/// A single app tile: icon image plus label. The icon shape follows the chosen
/// layout style (Classic = native icon, Glass = translucent tile, Android = circular).
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
        case .glass:   return iconSize * 0.22    // liquid-glass rounded square
        case .android: return iconSize * 0.5     // circle
        case .windows: return iconSize * 0.12    // rounded square tile
        case .cyber:   return iconSize * 0.16    // neon tile
        }
    }
    private var labelColor: Color {
        switch style {
        case .cyber: return CyberPalette.text
        case .glass: return GlassPalette.sheen
        default: return .white
        }
    }
    private var displayIcon: NSImage { store.icon(for: app) }

    var body: some View {
        VStack(spacing: style == .android ? 8 : 7) {
            ZStack {
                if highlight {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(highlightColor.opacity(0.9), lineWidth: 3)
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
                    .shadow(color: style == .glass ? GlassPalette.coolEdge.opacity(0.28) : .black.opacity(0.6),
                            radius: style == .glass ? 4 : 2, x: 0, y: 1)
                    .frame(maxWidth: iconSize + 26)
            }
        }
        .contentShape(Rectangle())
    }

    private var highlightColor: Color {
        switch style {
        case .cyber: return CyberPalette.neon
        case .glass: return GlassPalette.coolEdge
        default: return .white
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        switch style {
        case .classic:
            Image(nsImage: displayIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        case .glass:
            ZStack {
                LiquidGlassBackground(
                    shape: RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous),
                    tint: GlassPalette.coolEdge,
                    transparency: store.settings.glassTransparency,
                    reduceLiveBlur: store.settings.usesVideoBackground,
                    strokeOpacity: 0.42,
                    shadowOpacity: 0.20
                )
                Image(nsImage: displayIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize * 0.68, height: iconSize * 0.68)
                    .shadow(color: .white.opacity(0.28), radius: 6)
            }
            .frame(width: iconSize, height: iconSize)
        case .android:
            // Circular icons (icon fills a circle).
            Image(nsImage: displayIcon)
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
                Image(nsImage: displayIcon)
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
                Image(nsImage: displayIcon)
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
        case .glass:   return mainCell * 0.22
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

        let style = store.settings.layoutStyle
        let isCyber = style == .cyber
        let isGlass = style == .glass
        let accent = folder.colorHex.map { Color(hex: $0) } ?? CyberPalette.neon
        let glassAccent = folder.colorHex.map { Color(hex: $0) } ?? GlassPalette.coolEdge
        let fillColor = isCyber ? CyberPalette.tile.opacity(0.6)
            : (folder.colorHex.map { Color(hex: $0).opacity(0.55) } ?? Color.white.opacity(0.16))
        let glassStrokeOpacity = GlassPalette.adjustedOpacity(
            highlight ? 0.95 : 0.34,
            transparency: store.settings.glassTransparency,
            reduction: highlight ? 0.15 : 0.35
        )
        let strokeColor = isCyber ? accent.opacity(0.9)
            : (isGlass ? GlassPalette.sheen.opacity(glassStrokeOpacity) : Color.white.opacity(highlight ? 0.9 : 0.18))
        let strokeW: CGFloat = (isCyber || isGlass) ? 1.5 : (highlight ? 3 : 1)

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: rad, style: .continuous)
                    .fill(isGlass ? Color.clear : fillColor)
                    .background {
                        if isGlass {
                            LiquidGlassBackground(
                                shape: RoundedRectangle(cornerRadius: rad, style: .continuous),
                                tint: glassAccent,
                                transparency: store.settings.glassTransparency,
                                reduceLiveBlur: store.settings.usesVideoBackground,
                                materialOpacity: 0.45,
                                sheenOpacity: 0.10,
                                tintOpacity: 0.035,
                                warmOpacity: 0.018,
                                innerStrokeOpacity: 0.05,
                                strokeOpacity: 0.18,
                                shadowOpacity: 0.04
                            )
                        }
                    }
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
                                        Image(nsImage: store.icon(for: app))
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
                    .foregroundColor(isCyber ? CyberPalette.text : (isGlass ? GlassPalette.sheen : .white))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: isGlass ? GlassPalette.coolEdge.opacity(0.28) : .black.opacity(0.6),
                            radius: isGlass ? 4 : 2, x: 0, y: 1)
                    .frame(maxWidth: iconSize + 26)
            }
        }
        .contentShape(Rectangle())
    }
}
