import SwiftUI

/// A single app tile: icon image plus label, in the classic Launchpad style.
struct AppIconView: View {
    let app: AppInfo
    let iconSize: CGFloat
    var highlight: Bool = false
    var showLabel: Bool = true

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                if highlight {
                    RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: iconSize + 14, height: iconSize + 14)
                }
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
            }
            if showLabel {
                Text(app.name)
                    .font(.system(size: 12.5, weight: .regular))
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

/// A folder tile showing a 3×3 mini preview of its first apps, plus the folder name.
struct FolderIconView: View {
    @EnvironmentObject var store: LaunchpadStore
    let folder: Folder
    let iconSize: CGFloat
    var highlight: Bool = false
    var showLabel: Bool = true

    var body: some View {
        let mini = folder.appIds.prefix(9).compactMap { store.app($0) }
        let pad = iconSize * 0.13
        let gap = iconSize * 0.06
        let mainCell = iconSize * 0.92

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: mainCell * 0.24, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: mainCell * 0.24, style: .continuous)
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
                                    Image(nsImage: mini[idx].icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
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
