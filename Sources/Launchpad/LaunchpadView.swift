import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root Launchpad view: frosted background, search field, paged app grid, page dots,
/// and the folder overlay.
struct LaunchpadView: View {
    @EnvironmentObject var store: LaunchpadStore
    @FocusState private var searchFocused: Bool
    var videoHandledExternally: Bool = false

    var body: some View {
        ZStack {
            // Background (blur / theme / image / solid / slideshow / video) + dim.
            // Per-page override applies only on the normal paged grid.
            BackgroundView(
                settings: store.settings,
                pageIndex: (store.isSearching || store.openFolderID != nil) ? nil : store.currentPage,
                videoHandledExternally: videoHandledExternally
            )
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
            .modifier(OpenTransition(style: store.settings.openAnimation, presented: store.presented))

            // Settings (gear) button, top-right.
            VStack {
                HStack {
                    Spacer()
                    Button { store.showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background {
                                if store.settings.layoutStyle == .glass {
                                    LiquidGlassBackground(shape: Circle(), tint: GlassPalette.coolEdge,
                                                          transparency: store.settings.glassTransparency,
                                                          strokeOpacity: 0.42, shadowOpacity: 0.20)
                                } else {
                                    Circle().fill(Color.black.opacity(0.32))
                                }
                            }
                            .overlay(
                                Circle().stroke(
                                    Color.white.opacity(store.settings.layoutStyle == .glass
                                        ? GlassPalette.adjustedOpacity(0.25, transparency: store.settings.glassTransparency, reduction: 0.35)
                                        : 0.25),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(store.t(.customizeHelp))
                }
                Spacer()
            }
            // Push below the menu bar / notch strip so the gear is never clipped
            // off the top of the screen (matches the search field's top clearance).
            .padding(.top, 64)
            .padding(.trailing, 28)
            .opacity(store.presented && !store.isSearching && store.openFolderID == nil && !store.showSettings && !store.showOnboarding ? 1 : 0)

            // Customization panel.
            if store.showSettings {
                SettingsView()
            }

            // Add / edit a custom launcher item (app / script / URL).
            if store.showItemEditor {
                AddEditItemView()
            }

            // First-run onboarding / permissions dialog.
            if store.showOnboarding {
                OnboardingView()
            }
        }
        .onDrop(of: [UTType.text], delegate: RootDropDelegate(store: store))
        .onAppear {
            searchFocused = true
            withAnimation(store.settings.openAnim) { store.presented = true }
        }
        .onChange(of: store.searchText) { _ in store.currentPage = 0 }
        .animation(store.settings.anim(0.2), value: store.openFolderID)
        .animation(store.settings.anim(0.2), value: store.showSettings)
        .animation(store.settings.anim(0.2), value: store.showItemEditor)
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
            // Base page offset + live finger-follow offset during a trackpad swipe.
            // Page commits are animated via withAnimation in the store, so no implicit
            // .animation here (which would fight the interactive drag).
            .offset(x: -CGFloat(store.currentPage) * areaSize.width + store.pageDragOffset)
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
                .contextMenu { pageMenu }

            ForEach(Array(items.enumerated()), id: \.element) { idx, id in
                tileView(for: id)
                    .frame(width: geo.cellWidth, height: geo.cellHeight)
                    .position(store.tilePosition(for: id, index: idx, geo: geo, area: areaSize))
                    .opacity(store.draggingID == id ? 0.28 : 1)
            }

            // User-placed widgets float above the icon grid on this page (not in search).
            if !store.isSearching {
                WidgetLayer(pageIndex: pageIndex, areaSize: areaSize)
            }
        }
        .frame(width: areaSize.width, height: areaSize.height)
        // Page-local space so the widget rotation handle reads cursor position in the
        // same coordinates as widget centres (widget.x * areaSize).
        .coordinateSpace(name: WidgetLayer.coordinateSpace)
        .animation(store.settings.anim(0.2), value: items)
        .onDrop(
            of: [UTType.text],
            delegate: GridDropDelegate(store: store, page: pageIndex, areaSize: areaSize)
        )
    }

    /// Right-click menu on an empty area of the page: add an item, or set this page's
    /// background (image / preset colour / clear).
    @ViewBuilder
    private var pageMenu: some View {
        Button(store.t(.addItem)) { store.beginAddItem() }
        Menu(store.t(.addWidget)) {
            Button(store.t(.widgetClock)) { store.addWidget(.clock, page: pageIndex) }
            Button(store.t(.widgetDate)) { store.addWidget(.date, page: pageIndex) }
            Button(store.t(.widgetNotes)) { store.addWidget(.notes, page: pageIndex) }
            Button(store.t(.widgetBattery)) { store.addWidget(.battery, page: pageIndex) }
            Button(store.t(.widgetSystem)) { store.addWidget(.system, page: pageIndex) }
            Button(store.t(.widgetWeather)) { store.addWidget(.weather, page: pageIndex) }
            Divider()
            Button(store.t(.widgetImage)) { store.addMediaWidget(.image, page: pageIndex) }
            Button(store.t(.widgetVideo)) { store.addMediaWidget(.video, page: pageIndex) }
        }
        Divider()
        Menu(store.t(.pageBackground)) {
            Button(store.t(.pageBgImage)) { store.setPageBackgroundImage(pageIndex) }
            ForEach(PageGrid.pageColorPalette, id: \.hex) { c in
                Button { store.setPageBackgroundColor(pageIndex, hex: c.hex) } label: { Text(c.name) }
            }
            if store.pageHasBackground(pageIndex) {
                Divider()
                Button(store.t(.pageBgClear)) { store.clearPageBackground(pageIndex) }
            }
        }
    }

    static let pageColorPalette: [(name: String, hex: String)] = [
        ("Midnight", "#0B1026"), ("Indigo", "#1A1340"), ("Forest", "#064E3B"),
        ("Purple", "#7C3AED"), ("Blue", "#0A84FF"), ("Rose", "#9D174D"), ("Graphite", "#2B2B2E"),
    ]

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
            .contextMenu { itemMenu(for: id, app: app) }
        } else if let folder = store.folder(id) {
            FolderIconView(
                folder: folder,
                iconSize: geo.cellWidth * 0.62,
                highlight: store.folderCandidateID == id,
                showLabel: store.settings.showLabels
            )
            .onTapGesture { if !store.isDragging { store.openFolder(id) } }
            .onDrag {
                store.beginDrag(id)
                return NSItemProvider(object: id as NSString)
            }
            .contextMenu {
                Button(store.t(.editItem)) { store.openFolder(id) }
                Divider()
                Button(store.t(.addItem)) { store.beginAddItem() }
            }
        } else {
            Color.clear
        }
    }

    /// Right-click menu for an app / custom-item tile.
    @ViewBuilder
    private func itemMenu(for id: String, app: AppInfo) -> some View {
        if store.isCustom(id) {
            Button(store.t(.editItem)) { store.beginEditItem(id) }
            Button(store.t(.deleteItem), role: .destructive) { store.removeCustomItem(id) }
        } else {
            Button(store.t(.revealInFinder)) {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
        }
        Button(store.t(.chooseIcon)) { store.chooseIconOverride(for: id) }
        if store.hasIconOverride(id) {
            Button(store.t(.clearIcon)) { store.clearIconOverride(for: id) }
        }
        Button(store.t(.hide)) { store.hide(id) }
        Divider()
        Button(store.t(.addItem)) { store.beginAddItem() }
    }
}

/// Search box pinned at the top centre.
struct SearchField: View {
    @EnvironmentObject var store: LaunchpadStore
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    private var isGlass: Bool { store.settings.layoutStyle == .glass }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField(store.t(.search), text: $text)
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
        .background {
            if isGlass {
                LiquidGlassBackground(shape: Capsule(), tint: GlassPalette.coolEdge,
                                      transparency: store.settings.glassTransparency,
                                      strokeOpacity: 0.40, shadowOpacity: 0.16)
            } else {
                Capsule().fill(Color.white.opacity(0.16))
            }
        }
        .overlay(
            Capsule().stroke(
                Color.white.opacity(isGlass
                    ? GlassPalette.adjustedOpacity(0.28, transparency: store.settings.glassTransparency, reduction: 0.35)
                    : 0.12),
                lineWidth: 1
            )
        )
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
                    .onTapGesture { store.goToPage(i) }
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
