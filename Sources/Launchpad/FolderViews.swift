import SwiftUI
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

    // Fixed folder-grid metrics → constant card size regardless of item count.
    private let cols = 5
    private let rows = 4
    private let cell: CGFloat = 96
    private let hSpacing: CGFloat = 22
    private let vSpacing: CGFloat = 18
    private let sidePad: CGFloat = 40    // left/right inner margin (also the drop area)
    private let headerPad: CGFloat = 132 // top space reserved for back / name / colour row
    private let bottomPad: CGFloat = 44  // space reserved for page dots

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
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.closeAllFolders() }
                .onDrop(of: [UTType.text], delegate: FolderMoveOutDropDelegate(store: store))

            // The folder card (fixed size).
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
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
            .animation(.easeInOut(duration: 0.2), value: items)
            .animation(.easeInOut(duration: 0.25), value: store.folderPage)
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
                            .background(Circle().fill(Color.black.opacity(0.28)))
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
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: 320)

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
            .frame(width: 22, height: 22)
            .overlay(
                Circle().stroke(Color.white.opacity(selected ? 0.95 : 0.3),
                                lineWidth: selected ? 3 : 1)
            )
            .overlay(
                Group {
                    if hex == nil {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            )
            .help(hex == nil ? store.t(.defaultColor) : store.t(.folderColor))
            .onTapGesture { store.setFolderColor(folder.id, hex: hex) }
    }
}
