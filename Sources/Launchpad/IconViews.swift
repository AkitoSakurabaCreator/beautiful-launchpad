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
        }
    }

    var body: some View {
        VStack(spacing: style == .android ? 8 : 7) {
            ZStack {
                if highlight {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: iconSize + 14, height: iconSize + 14)
                }
                iconImage
            }
            if showLabel {
                Text(app.name)
                    .font(.system(size: 12.5, weight: style == .android ? .medium : .regular))
                    .foregroundColor(.white)
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

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: rad, style: .continuous)
                    .fill(folder.colorHex.map { Color(hex: $0).opacity(0.55) } ?? Color.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: rad, style: .continuous)
                            .stroke(Color.white.opacity(highlight ? 0.9 : 0.18),
                                    lineWidth: highlight ? 3 : 1)
                    )
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: iconSize + 26)
            }
        }
        .contentShape(Rectangle())
    }
}
