import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Full-screen overlay shown when a folder is opened. The contained items are laid
/// out on a *fixed-size* grid (so the card never overflows no matter how many apps
/// it holds — extra items spill onto additional pages) and positioned with exact
/// grid maths so drag hit-testing matches. A single geometry-driven drop delegate
/// covers the whole card (reliable reorder + nesting), while the backdrop catches
/// "drop outside → move the item out of the folder".
///
/// Interactions:
/// • drag onto another item's centre → make / enter a sub-folder (nesting)
/// • drag elsewhere on the card       → reorder
/// • drag to the left/right edge      → flip to the previous / next folder page
/// • drag onto the dark backdrop      → move the item out of the folder
/// • tap a sub-folder                 → drill in (a ‹ back button returns one level)
struct FolderOverlayView: View {
    @EnvironmentObject var store: LaunchpadStore
    let folder: Folder
    @State private var hoveredRemove: String? = nil

    // Folder-grid metrics. Columns/rows are user-adjustable (Settings → folder size).
    private var cols: Int { store.settings.folderColumns }
    private var rows: Int { store.settings.folderRows }

    // Base (unscaled) metrics.
    private let baseCell: CGFloat = 96
    private let baseHSpacing: CGFloat = 22
    private let baseVSpacing: CGFloat = 18
    private let baseSidePad: CGFloat = 40
    private let baseHeaderPad: CGFloat = 132
    private let baseBottomPad: CGFloat = 44

    private var screenSize: CGSize { NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900) }
    private var baseGridW: CGFloat { CGFloat(cols) * baseCell + CGFloat(cols - 1) * baseHSpacing }
    private var baseGridH: CGFloat { CGFloat(rows) * baseCell + CGFloat(rows - 1) * baseVSpacing }
    private var baseCardW: CGFloat { baseGridW + baseSidePad * 2 }
    private var baseCardH: CGFloat { baseHeaderPad + baseGridH + baseBottomPad }

    /// Shrink the whole card uniformly so it always fits the screen. Prevents both the
    /// card overflowing AND the over-tall-card-inflates-the-background bug for large
    /// folder grids (e.g. 8×6) on small displays. The drop delegate uses this same
    /// scaled geometry, so hit-testing stays consistent.
    private var fit: CGFloat {
        min(1, screenSize.width * 0.92 / baseCardW, screenSize.height * 0.88 / baseCardH)
    }

    private var cell: CGFloat { baseCell * fit }
    private var hSpacing: CGFloat { baseHSpacing * fit }
    private var vSpacing: CGFloat { baseVSpacing * fit }
    private var sidePad: CGFloat { baseSidePad * fit }
    private var headerPad: CGFloat { baseHeaderPad * fit }
    private var bottomPad: CGFloat { baseBottomPad * fit }
    private var isGlass: Bool { store.settings.layoutStyle == .glass }
    private var glassTransparency: Double { store.settings.glassTransparency }

    private var gridW: CGFloat { CGFloat(cols) * cell + CGFloat(cols - 1) * hSpacing }
    private var gridH: CGFloat { CGFloat(rows) * cell + CGFloat(rows - 1) * vSpacing }
    private var cardW: CGFloat { gridW + sidePad * 2 }
    private var cardH: CGFloat { headerPad + gridH + bottomPad }

    /// Preset folder tints (plus a "default" clear option).
    private let palette: [String] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF2D55",
    ]

    private func makeGeo() -> GridGeometry {
        var g = GridGeometry()
        g.columns = cols
        g.rows = rows
        g.cellWidth = cell
        g.cellHeight = cell
        g.hSpacing = hSpacing
        g.vSpacing = vSpacing
        g.leftPad = sidePad
        g.topPad = headerPad
        return g
    }

    var body: some View {
        // Side-effect: share geometry with the folder drop delegate (non-published).
        let g = makeGeo()
        store.folderGeo = g
        store.folderAreaSize = CGSize(width: cardW, height: cardH)

        let pages = store.folderPages()
        let page = min(max(0, store.folderPage), max(0, pages.count - 1))
        let items = pages.indices.contains(page) ? pages[page] : []

        return ZStack {
            // Backdrop: tap closes the overlay; dropping here pulls the item out.
            Color.black.opacity(isGlass ? GlassPalette.adjustedOpacity(0.08, transparency: glassTransparency, reduction: 0.75) : 0.5)
                .ignoresSafeArea()
                .onTapGesture { store.closeAllFolders() }
                .onDrop(of: [UTType.text], delegate: FolderMoveOutDropDelegate(store: store))

            // The folder card (fixed size).
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(isGlass ? Color.clear : Color.white.opacity(0.001))
                    .background {
                        if isGlass {
                            LiquidGlassBackground(
                                shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
                                tint: GlassPalette.coolEdge,
                                transparency: glassTransparency,
                                materialOpacity: 0.42,
                                sheenOpacity: 0.10,
                                tintOpacity: 0.035,
                                warmOpacity: 0.018,
                                innerStrokeOpacity: 0.06,
                                strokeOpacity: 0.18,
                                shadowOpacity: 0.05
                            )
                        } else {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                Color.white.opacity(isGlass
                                    ? GlassPalette.adjustedOpacity(0.10, transparency: glassTransparency, reduction: 0.35)
                                    : 0.15),
                                lineWidth: 1
                            )
                    )
                    .frame(width: cardW, height: cardH)

                header
                    .frame(width: cardW)
                    .padding(.top, 16)

                // Item tiles, positioned by exact grid maths (matches hit-testing).
                ForEach(Array(items.enumerated()), id: \.element) { idx, id in
                    tile(for: id)
                        .frame(width: cell, height: cell)
                        .position(g.cellCenter(forIndex: idx))
                        .opacity(store.folderDraggingID == id ? 0.28 : 1)
                }

                if pages.count > 1 {
                    pageDots(count: pages.count, current: page)
                        .frame(width: cardW, height: cardH, alignment: .bottom)
                        .padding(.bottom, 12)
                        .allowsHitTesting(true)
                }
            }
            .frame(width: cardW, height: cardH)
            .contentShape(Rectangle())
            // One delegate for the whole card → robust reorder / nesting.
            .onDrop(
                of: [UTType.text],
                delegate: FolderGridDropDelegate(store: store, areaSize: CGSize(width: cardW, height: cardH))
            )
            .animation(store.settings.anim(0.2), value: items)
            .animation(store.settings.anim(0.25), value: store.folderPage)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    // MARK: - Header (back button + editable name + colour row)

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if store.folderPath.count > 1 {
                    Button { store.closeFolder() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background {
                                if isGlass {
                                    LiquidGlassBackground(shape: Circle(), tint: GlassPalette.coolEdge,
                                                          transparency: glassTransparency,
                                                          materialOpacity: 0.35,
                                                          sheenOpacity: 0.09,
                                                          tintOpacity: 0.03,
                                                          warmOpacity: 0.015,
                                                          innerStrokeOpacity: 0.05,
                                                          strokeOpacity: 0.18,
                                                          shadowOpacity: 0.04)
                                } else {
                                    Circle().fill(Color.black.opacity(0.28))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(store.t(.back))
                }
                Spacer()
            }
            .padding(.horizontal, sidePad)

            TextField(
                "",
                text: Binding(
                    get: { store.folder(folder.id)?.name ?? "" },
                    set: { store.renameFolder(folder.id, $0) }
                )
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 22 * fit, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: 320 * fit)

            colorRow
        }
    }

    // MARK: - One item (app / custom item, or a nested folder)

    @ViewBuilder
    private func tile(for id: String) -> some View {
        if store.isFolder(id), let sub = store.folder(id) {
            FolderIconView(
                folder: sub,
                iconSize: cell * 0.62,
                highlight: store.folderMergeCandidateID == id,
                showLabel: store.settings.showLabels
            )
            .onTapGesture { if !store.isFolderDragging { store.openFolder(id) } }
            .onDrag {
                store.beginFolderDrag(id)
                return NSItemProvider(object: id as NSString)
            }
        } else if let app = store.app(id) {
            ZStack(alignment: .topTrailing) {
                AppIconView(
                    app: app,
                    iconSize: cell * 0.62,
                    highlight: store.folderMergeCandidateID == id,
                    showLabel: store.settings.showLabels
                )
                .onTapGesture { if !store.isFolderDragging { store.launch(id) } }

                Button {
                    store.removeFromFolder(id, folder.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .opacity(hoveredRemove == id ? 1 : 0.0)
                .offset(x: 6, y: -4)
            }
            .onHover { hoveredRemove = $0 ? id : nil }
            .onDrag {
                store.beginFolderDrag(id)
                return NSItemProvider(object: id as NSString)
            }
            .contextMenu {
                Button(store.t(.hide)) { store.hide(id) }
                Button(store.t(.chooseIcon)) { store.chooseIconOverride(for: id) }
                if store.hasIconOverride(id) {
                    Button(store.t(.clearIcon)) { store.clearIconOverride(for: id) }
                }
                if store.isCustom(id) {
                    Button(store.t(.deleteItem), role: .destructive) { store.removeCustomItem(id) }
                }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Page dots (folder contents paginate when they exceed one page)

    private func pageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == current ? 0.95 : 0.32))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation { store.folderPage = i } }
            }
        }
    }

    /// A row of preset folder tints; first swatch clears back to the default.
    private var colorRow: some View {
        HStack(spacing: 9) {
            swatch(nil)
            ForEach(palette, id: \.self) { swatch($0) }
        }
    }

    @ViewBuilder
    private func swatch(_ hex: String?) -> some View {
        let current = store.folder(folder.id)?.colorHex
        let selected = hex == current
        Circle()
            .fill(hex.map { Color(hex: $0) } ?? Color.white.opacity(0.18))
            .frame(width: 22 * fit, height: 22 * fit)
            .overlay(
                Circle().stroke(Color.white.opacity(selected ? 0.95 : 0.3),
                                lineWidth: selected ? 3 : 1)
            )
            .overlay(
                Group {
                    if hex == nil {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 11 * fit))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            )
            .help(hex == nil ? store.t(.defaultColor) : store.t(.folderColor))
            .onTapGesture { store.setFolderColor(folder.id, hex: hex) }
    }
}
