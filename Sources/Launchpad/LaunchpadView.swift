import SwiftUI
import UniformTypeIdentifiers

/// Root Launchpad view: frosted background, search field, paged app grid, page dots,
/// and the folder overlay.
struct LaunchpadView: View {
    @EnvironmentObject var store: LaunchpadStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            // Background (desktop blur / theme / image / solid) + dim: fades in/out.
            BackgroundView(settings: store.settings)
                .opacity(store.presented ? 1 : 0)

            // Foreground content: fades + subtle zoom (classic Launchpad feel).
            ZStack {
                VStack(spacing: 14) {
                    SearchField(text: $store.searchText, focused: $searchFocused)
                        .frame(width: 380)
                        // Clear the menu bar / notch at the top of the full-screen window.
                        .padding(.top, 72)

                    GeometryReader { proxy in
                        PagerArea(areaSize: proxy.size)
                    }

                    PageDots()
                        .padding(.bottom, 22)
                }

                if let fid = store.openFolderID, let folder = store.folder(fid) {
                    FolderOverlayView(folder: folder)
                }
            }
            .opacity(store.presented ? 1 : 0)
            .scaleEffect(store.presented ? 1 : 0.92)

            // Settings (gear) button, top-right.
            VStack {
                HStack {
                    Spacer()
                    Button { store.showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.32)))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("カスタマイズ (⌘,)")
                }
                Spacer()
            }
            // Push below the menu bar / notch strip so the gear is never clipped
            // off the top of the screen (matches the search field's top clearance).
            .padding(.top, 64)
            .padding(.trailing, 28)
            .opacity(store.presented && !store.isSearching && store.openFolderID == nil ? 1 : 0)

            // Customization panel.
            if store.showSettings {
                SettingsView()
            }
        }
        .onDrop(of: [UTType.text], delegate: RootDropDelegate(store: store))
        .onAppear {
            searchFocused = true
            withAnimation(.easeOut(duration: 0.24)) { store.presented = true }
        }
        .onChange(of: store.searchText) { _ in store.currentPage = 0 }
        .animation(.easeInOut(duration: 0.2), value: store.openFolderID)
        .animation(.easeInOut(duration: 0.2), value: store.showSettings)
    }
}

/// The horizontally-paged grid region. Computes geometry from its size, shares it
/// with the drop delegate, and lays the pages out side-by-side with an offset.
struct PagerArea: View {
    @EnvironmentObject var store: LaunchpadStore
    let areaSize: CGSize

    var body: some View {
        let g = computeGeometry(areaSize,
                                columns: store.settings.columns,
                                rows: store.settings.rows)
        // Side-effect: share geometry with the drop delegate. `geo`/`areaSize` are
        // plain (non-published) so this does not trigger a re-render loop.
        store.geo = g
        store.areaSize = areaSize

        let pages = store.pages(geo: g)

        return ZStack {
            HStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, items in
                    PageGrid(items: items, geo: g, areaSize: areaSize, pageIndex: pageIndex)
                        .frame(width: areaSize.width, height: areaSize.height)
                }
            }
            .frame(width: areaSize.width, alignment: .leading)
            .offset(x: -CGFloat(store.currentPage) * areaSize.width)
            .animation(.easeInOut(duration: 0.28), value: store.currentPage)
        }
        .frame(width: areaSize.width, height: areaSize.height)
        .clipped()
    }
}

/// A single page: tiles positioned by exact grid maths so drag hit-testing matches.
struct PageGrid: View {
    @EnvironmentObject var store: LaunchpadStore
    let items: [String]
    let geo: GridGeometry
    let areaSize: CGSize
    let pageIndex: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.backgroundTap() }

            ForEach(Array(items.enumerated()), id: \.element) { idx, id in
                tileView(for: id)
                    .frame(width: geo.cellWidth, height: geo.cellHeight)
                    .position(geo.cellCenter(forIndex: idx))
                    .opacity(store.draggingID == id ? 0.28 : 1)
            }
        }
        .frame(width: areaSize.width, height: areaSize.height)
        .animation(.easeInOut(duration: 0.2), value: items)
        .onDrop(
            of: [UTType.text],
            delegate: GridDropDelegate(store: store, page: pageIndex, areaSize: areaSize)
        )
    }

    @ViewBuilder
    private func tileView(for id: String) -> some View {
        if let app = store.app(id) {
            AppIconView(
                app: app,
                iconSize: geo.cellWidth * 0.62,
                highlight: store.folderCandidateID == id,
                showLabel: store.settings.showLabels
            )
            .onTapGesture { if !store.isDragging { store.launch(id) } }
            .onDrag {
                store.beginDrag(id)
                return NSItemProvider(object: id as NSString)
            }
        } else if let folder = store.folder(id) {
            FolderIconView(
                folder: folder,
                iconSize: geo.cellWidth * 0.62,
                highlight: store.folderCandidateID == id,
                showLabel: store.settings.showLabels
            )
            .onTapGesture { if !store.isDragging { store.openFolderID = id } }
            .onDrag {
                store.beginDrag(id)
                return NSItemProvider(object: id as NSString)
            }
        } else {
            Color.clear
        }
    }
}

/// Search box pinned at the top centre.
struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("検索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .focused(focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.16)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Page indicator dots; click to jump to a page.
struct PageDots: View {
    @EnvironmentObject var store: LaunchpadStore

    var body: some View {
        let count = max(1, store.pages(geo: store.geo).count)
        HStack(spacing: 11) {
            ForEach(Array(0..<count), id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == store.currentPage ? 0.95 : 0.32))
                    .frame(width: 8, height: 8)
                    .onTapGesture { withAnimation { store.currentPage = i } }
            }
        }
        .frame(height: 14)
        .opacity(store.isSearching ? 0 : 1)
    }
}

/// Derive the grid layout (cell size, padding) from the available area.
private func computeGeometry(_ size: CGSize, columns: Int = 7, rows: Int = 5) -> GridGeometry {
    let cols = max(1, columns)
    let rowCount = max(1, rows)

    var g = GridGeometry()
    // Store the clamped values, not the raw inputs: downstream consumers
    // (cellCenter, drag hit-testing) divide/mod and index by these, so the
    // geometry must never carry a zero column/row count.
    g.columns = cols
    g.rows = rowCount
    guard size.width > 80, size.height > 80 else { return g }

    let hSpacing: CGFloat = 28
    let vSpacing: CGFloat = 22

    let cellW0 = (size.width * 0.86 - CGFloat(cols - 1) * hSpacing) / CGFloat(cols)
    let cellH0 = (size.height * 0.92 - CGFloat(rowCount - 1) * vSpacing) / CGFloat(rowCount)
    let cell = max(56, min(cellW0, cellH0, 152))

    g.cellWidth = cell
    g.cellHeight = cell
    g.hSpacing = hSpacing
    g.vSpacing = vSpacing

    let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * hSpacing
    let gridH = CGFloat(rowCount) * cell + CGFloat(rowCount - 1) * vSpacing
    g.leftPad = max(0, (size.width - gridW) / 2)
    g.topPad = max(0, (size.height - gridH) / 2)
    return g
}
