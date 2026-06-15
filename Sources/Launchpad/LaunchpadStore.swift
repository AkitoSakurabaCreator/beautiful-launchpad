import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Central observable state for the Launchpad: discovered apps, top-level layout,
/// folders, search, paging, and the drag-and-drop interaction model.
///
/// All access happens on the main thread (AppKit/SwiftUI), so explicit actor
/// isolation is unnecessary and would complicate the non-isolated app entry point.
final class LaunchpadStore: ObservableObject {
    // Catalogue
    @Published private(set) var appsById: [String: AppInfo] = [:]

    // Layout
    @Published var order: [String] = []          // top-level ids (app path | folder id)
    @Published var folders: [String: Folder] = [:]

    // UI state
    @Published var searchText: String = ""
    @Published var currentPage: Int = 0
    @Published var openFolderID: String? = nil

    /// Drives the open/close fade + zoom animation (classic Launchpad feel).
    @Published var presented: Bool = false
    private var closing = false

    // Appearance / customization
    @Published var settings = AppSettings()
    @Published var showSettings = false

    // Drag state
    @Published var draggingID: String? = nil
    @Published var dragPreviewOrder: [String]? = nil
    @Published var folderCandidateID: String? = nil
    var isDragging: Bool { draggingID != nil }

    // Folder-internal drag: move an app out of, or reorder within, an open folder.
    @Published var folderDragApp: String? = nil
    private var folderDragFolder: String? = nil

    /// Called to close/quit the Launchpad (injected by the AppDelegate).
    var onDismiss: (() -> Void)?

    /// Geometry + container size, written by the view each layout pass and read by
    /// the drop delegate. Plain (non-published) to avoid re-render loops.
    var geo = GridGeometry()
    var areaSize: CGSize = .zero

    private var lastFlip = Date.distantPast
    private var scrollAccum: CGFloat = 0
    private var scrollLatched = false

    // MARK: - Catalogue lookups

    func app(_ id: String) -> AppInfo? { appsById[id] }
    func folder(_ id: String) -> Folder? { folders[id] }
    func isApp(_ id: String) -> Bool { appsById[id] != nil }
    func isFolder(_ id: String) -> Bool { folders[id] != nil }

    /// Localized UI string for the current language preference (live-switchable).
    func t(_ key: L.Key) -> String { L.t(key, settings.language) }

    // MARK: - Loading & persistence

    func loadAndScan() {
        settings = Self.loadSettings() ?? AppSettings()
        let scanned = AppScanner.scan()
        var byId: [String: AppInfo] = [:]
        for a in scanned { byId[a.id] = a }
        appsById = byId
        reconcile(scanned: scanned, persisted: Self.loadPersisted())
        clampPage()
    }

    private func reconcile(scanned: [AppInfo], persisted: PersistedLayout?) {
        let available = Set(scanned.map { $0.id })
        var newFolders: [String: Folder] = [:]
        var newOrder: [String] = []
        var placed = Set<String>()

        if let p = persisted {
            // Rebuild folders, keeping only apps that still exist.
            for f in p.folders {
                let valid = f.appIds.filter { available.contains($0) }
                if valid.count >= 2 {
                    newFolders[f.id] = Folder(id: f.id, name: f.name, appIds: valid)
                    valid.forEach { placed.insert($0) }
                }
            }
            // Re-apply saved top-level order.
            for id in p.order {
                if id.hasPrefix("folder-") {
                    if newFolders[id] != nil, !placed.contains(id) {
                        newOrder.append(id)
                        placed.insert(id)
                    }
                } else if available.contains(id), !placed.contains(id) {
                    newOrder.append(id)
                    placed.insert(id)
                }
            }
            // A folder that lost members down to a single app dissolves back to that app.
            for f in p.folders {
                let valid = f.appIds.filter { available.contains($0) }
                if valid.count == 1, let only = valid.first, !placed.contains(only) {
                    newOrder.append(only)
                    placed.insert(only)
                }
            }
            // Safety net: a rebuilt folder whose id was missing from the saved
            // `order` (e.g. hand-edited or imported JSON) would otherwise vanish
            // along with its apps. Re-attach it at the end deterministically.
            for fid in newFolders.keys.sorted() where !placed.contains(fid) {
                newOrder.append(fid)
                placed.insert(fid)
            }
        }

        // Append any newly discovered apps (alphabetical scan order) not yet placed.
        for a in scanned where !placed.contains(a.id) {
            newOrder.append(a.id)
            placed.insert(a.id)
        }

        folders = newFolders
        order = newOrder
    }

    static func supportFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Launchpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    static func loadPersisted() -> PersistedLayout? {
        guard let data = try? Data(contentsOf: supportFileURL()) else { return nil }
        return try? JSONDecoder().decode(PersistedLayout.self, from: data)
    }

    func save() {
        let payload = PersistedLayout(order: order, folders: Array(folders.values))
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Self.supportFileURL(), options: .atomic)
        }
    }

    func resetLayout() {
        try? FileManager.default.removeItem(at: Self.supportFileURL())
        loadAndScan()
        currentPage = 0
        objectWillChange.send()
    }

    // MARK: - Settings persistence

    static func settingsFileURL() -> URL {
        supportFileURL().deletingLastPathComponent().appendingPathComponent("settings.json")
    }

    static func loadSettings() -> AppSettings? {
        guard let data = try? Data(contentsOf: settingsFileURL()) else { return nil }
        // Normalize the decoded value: a malformed on-disk file (e.g. columns: 0)
        // must not reach grid math. See AppSettings.normalized().
        return (try? JSONDecoder().decode(AppSettings.self, from: data))?.normalized()
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: Self.settingsFileURL(), options: .atomic)
        }
    }

    /// Mutate settings, persist, and re-clamp paging (column/row changes alter page size).
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var s = settings
        mutate(&s)
        settings = s.normalized()
        saveSettings()
        clampPage()
    }

    // MARK: - Export / Import (portable config for moving between Macs)

    func exportConfig() {
        let panel = NSSavePanel()
        panel.title = t(.exportPanelTitle)
        panel.nameFieldStringValue = "launchpad-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = ExportBundle(
            layout: PersistedLayout(order: order, folders: Array(folders.values)),
            settings: settings
        )
        if let data = try? JSONEncoder.pretty.encode(bundle) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.title = t(.importPanelTitle)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(ExportBundle.self, from: data)
        else { return }

        // Imported bundles are untrusted input — normalize before use/persist.
        settings = bundle.settings.normalized()
        saveSettings()
        applyImportedLayout(bundle.layout)
        save()
        currentPage = 0
        clampPage()
    }

    private func applyImportedLayout(_ persisted: PersistedLayout) {
        let scanned = Array(appsById.values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reconcile(scanned: scanned, persisted: persisted)
    }

    func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.title = t(.wallpaperPanelTitle)
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings {
            $0.wallpaperPath = url.path
            $0.backgroundKind = .image
        }
    }

    // MARK: - Derived data

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func searchResults() -> [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return appsById.values
            .filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { $0.id }
    }

    /// The list rendered at the top level (uses the live drag preview while dragging).
    func topLevelTiles() -> [String] {
        if isDragging, let preview = dragPreviewOrder { return preview }
        return order
    }

    func pages(geo: GridGeometry) -> [[String]] {
        let items = isSearching ? searchResults() : topLevelTiles()
        return chunk(items, geo.pageSize)
    }

    func clampPage() {
        let count = pages(geo: geo).count
        currentPage = min(max(0, currentPage), max(0, count - 1))
    }

    // MARK: - Actions

    func launch(_ appId: String) {
        guard let info = appsById[appId] else { return }
        NSWorkspace.shared.open(info.url)
        dismiss()
    }

    func launchFirstResult() {
        guard isSearching, let first = searchResults().first else { return }
        launch(first)
    }

    func dismiss() { requestClose() }

    /// Animate the Launchpad out, then actually close once the animation finishes.
    func requestClose() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: 0.2)) { presented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            self?.onDismiss?()
        }
    }

    func escape() {
        if showSettings { showSettings = false; return }
        if openFolderID != nil { openFolderID = nil; return }
        if isSearching { searchText = ""; currentPage = 0; return }
        dismiss()
    }

    func backgroundTap() {
        if openFolderID != nil { openFolderID = nil; return }
        dismiss()
    }

    func nextPage() {
        let count = pages(geo: geo).count
        if currentPage < count - 1 { currentPage += 1 }
    }

    func prevPage() {
        if currentPage > 0 { currentPage -= 1 }
    }

    /// Page navigation from scroll/swipe. Flips at most once per physical swipe to
    /// avoid the double-jump caused by inertial (momentum) scroll events.
    func handleScrollEvent(deltaX: CGFloat,
                           deltaY: CGFloat,
                           phase: NSEvent.Phase,
                           momentum: NSEvent.Phase,
                           precise: Bool) {
        guard !showSettings, openFolderID == nil else { return }
        // Ignore inertial momentum entirely — it is what produced the extra flip.
        if !momentum.isEmpty { return }

        if precise && !phase.isEmpty {
            // Trackpad: latch one flip per gesture (began → changed… → ended).
            if phase.contains(.began) {
                scrollAccum = 0
                scrollLatched = false
            }
            if phase.contains(.changed), !scrollLatched {
                if abs(deltaX) >= abs(deltaY) { scrollAccum += deltaX }
                if abs(scrollAccum) > 36 {
                    if scrollAccum < 0 { nextPage() } else { prevPage() }
                    scrollLatched = true
                }
            }
            if phase.contains(.ended) || phase.contains(.cancelled) {
                scrollAccum = 0
                scrollLatched = false
            }
        } else {
            // Classic mouse wheel (no phase info): debounce by time. Use whichever
            // axis dominates so a plain vertical-only wheel still flips pages
            // (most mice emit deltaY only; horizontal needs Shift).
            let now = Date()
            guard now.timeIntervalSince(lastFlip) > 0.45 else { return }
            let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
            if delta < -1 { lastFlip = now; nextPage() }
            else if delta > 1 { lastFlip = now; prevPage() }
        }
    }

    // MARK: - Folder mutations

    func defaultFolderName() -> String { t(.folderDefaultName) }

    func createFolder(keep targetApp: String, add draggedApp: String) {
        let fid = "folder-" + UUID().uuidString
        folders[fid] = Folder(id: fid, name: defaultFolderName(), appIds: [targetApp, draggedApp])
        var o = order
        if let idx = o.firstIndex(of: targetApp) {
            o[idx] = fid
        } else {
            o.append(fid)
        }
        o.removeAll { $0 == draggedApp }
        order = o
    }

    func addToFolder(appId: String, folderId: String) {
        guard var f = folders[folderId] else { return }
        if !f.appIds.contains(appId) { f.appIds.append(appId) }
        folders[folderId] = f
        order.removeAll { $0 == appId }
    }

    func removeFromFolder(_ appId: String, _ folderId: String) {
        guard var f = folders[folderId] else { return }
        f.appIds.removeAll { $0 == appId }

        var o = order
        if f.appIds.count <= 1 {
            // Dissolve folder: the lone remaining app takes the folder's slot.
            let leftover = f.appIds.first
            if let idx = o.firstIndex(of: folderId) {
                if let leftover { o[idx] = leftover } else { o.remove(at: idx) }
            }
            o.append(appId)
            folders[folderId] = nil
            openFolderID = nil
        } else {
            folders[folderId] = f
            if let idx = o.firstIndex(of: folderId) {
                o.insert(appId, at: min(idx + 1, o.count))
            } else {
                o.append(appId)
            }
        }
        order = o
        save()
    }

    func renameFolder(_ folderId: String, _ name: String) {
        guard var f = folders[folderId] else { return }
        f.name = name
        folders[folderId] = f
        save()
    }

    // MARK: - Folder-internal drag (drag apps out / reorder within an open folder)

    func beginFolderDrag(_ appId: String, folderId: String) {
        folderDragApp = appId
        folderDragFolder = folderId
    }

    func endFolderDrag() {
        folderDragApp = nil
        folderDragFolder = nil
    }

    /// Dropped outside the folder panel → pull the app back to the top-level grid.
    func dropFolderAppOut() {
        guard let appId = folderDragApp, let fid = folderDragFolder else { return }
        removeFromFolder(appId, fid)
        endFolderDrag()
    }

    /// Reorder within the same folder by inserting before the target app.
    func reorderInFolder(before targetId: String) {
        defer { endFolderDrag() }
        guard let appId = folderDragApp, let fid = folderDragFolder,
              var f = folders[fid], appId != targetId else { return }
        f.appIds.removeAll { $0 == appId }
        if let idx = f.appIds.firstIndex(of: targetId) {
            f.appIds.insert(appId, at: idx)
        } else {
            f.appIds.append(appId)
        }
        folders[fid] = f
        save()
    }

    // MARK: - Drag & drop

    func beginDrag(_ id: String) {
        guard !isSearching else { return }
        draggingID = id
        dragPreviewOrder = order
        folderCandidateID = nil
    }

    private func endDragReset() {
        draggingID = nil
        dragPreviewOrder = nil
        folderCandidateID = nil
    }

    /// Update folder-candidate / reorder preview from the current pointer location
    /// (in the page container's coordinate space).
    func updateDragPreview(point: CGPoint, containerSize: CGSize) {
        guard let dragging = draggingID else { return }

        // Edge zones flip pages mid-drag.
        let edge: CGFloat = 70
        if point.x < edge {
            flip(next: false)
        } else if point.x > containerSize.width - edge {
            flip(next: true)
        }

        let g = geo
        let working = order.filter { $0 != dragging }
        let size = g.pageSize
        let pagesW = chunk(working, size)
        let page = min(max(0, currentPage), max(0, pagesW.count - 1))
        let pageItems = pagesW.indices.contains(page) ? pagesW[page] : []

        let stepX = g.cellWidth + g.hSpacing
        let stepY = g.cellHeight + g.vSpacing
        var col = Int(floor((point.x - g.leftPad) / max(1, stepX)))
        var row = Int(floor((point.y - g.topPad) / max(1, stepY)))
        col = min(max(col, 0), g.columns - 1)
        row = min(max(row, 0), g.rows - 1)
        let cellIndex = row * g.columns + col

        // Folder candidate: hovering the centre of an existing app/folder.
        if cellIndex < pageItems.count {
            let hoveredId = pageItems[cellIndex]
            if hoveredId != dragging {
                let cellLeft = g.leftPad + CGFloat(col) * stepX
                let cellTop = g.topPad + CGFloat(row) * stepY
                let innerMX = g.cellWidth * 0.225
                let innerMY = g.cellHeight * 0.225
                let inInner =
                    point.x >= cellLeft + innerMX && point.x <= cellLeft + g.cellWidth - innerMX &&
                    point.y >= cellTop + innerMY && point.y <= cellTop + g.cellHeight - innerMY
                // App can merge into app (create) or into folder (add). Folders only reorder.
                let canMerge = isApp(dragging) && (isApp(hoveredId) || isFolder(hoveredId))
                if inInner && canMerge {
                    folderCandidateID = hoveredId
                    dragPreviewOrder = order
                    return
                }
            }
        }

        // Otherwise: reorder. Compute insertion index within the page.
        folderCandidateID = nil
        var localInsert = cellIndex
        let cellLeft = g.leftPad + CGFloat(col) * stepX
        if point.x > cellLeft + g.cellWidth / 2 { localInsert = cellIndex + 1 }
        localInsert = min(localInsert, pageItems.count)
        let globalInsert = min(page * size + localInsert, working.count)

        var preview = working
        preview.insert(dragging, at: globalInsert)
        dragPreviewOrder = preview
    }

    func commitDrop() {
        guard let dragging = draggingID else { endDragReset(); return }

        if let target = folderCandidateID, target != dragging {
            if isApp(dragging) && isApp(target) {
                createFolder(keep: target, add: dragging)
            } else if isApp(dragging), isFolder(target) {
                addToFolder(appId: dragging, folderId: target)
            } else if let preview = dragPreviewOrder {
                order = preview
            }
        } else if let preview = dragPreviewOrder {
            order = preview
        }

        endDragReset()
        clampPage()
        save()
    }

    func cancelDrag() {
        endDragReset()
    }

    private func flip(next: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastFlip) > 0.6 else { return }
        let count = chunk(order, geo.pageSize).count
        if next {
            if currentPage < count - 1 { currentPage += 1; lastFlip = now }
        } else {
            if currentPage > 0 { currentPage -= 1; lastFlip = now }
        }
    }
}
