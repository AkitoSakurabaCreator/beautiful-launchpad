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
    /// User-added entries (apps/scripts/URLs). Also synthesised into `appsById`
    /// so rendering/search/folders work, but launch dispatch keys off this map.
    @Published private(set) var customById: [String: CustomItem] = [:]

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

    /// Custom-item add/edit overlay. `editingItemId == nil` while adding a new one.
    @Published var showItemEditor = false
    @Published var editingItemId: String? = nil

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
        let persisted = Self.loadPersisted()
        let scanned = AppScanner.scan()
        var byId: [String: AppInfo] = [:]
        for a in scanned { byId[a.id] = a }
        appsById = byId
        mergeCustomIntoCatalogue(persisted?.customItems ?? [])
        reconcile(scanned: catalogueSorted(), persisted: persisted)
        clampPage()
    }

    /// Catalogue entries sorted by name (deterministic append order for reconcile).
    private func catalogueSorted() -> [AppInfo] {
        appsById.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Register custom items into `customById` and synthesise displayable `AppInfo`s
    /// into `appsById` (replacing any previous custom set).
    private func mergeCustomIntoCatalogue(_ items: [CustomItem]) {
        // Drop stale synthesised entries, then re-add the current set.
        for id in customById.keys { appsById[id] = nil }
        var custom: [String: CustomItem] = [:]
        for c in items {
            custom[c.id] = c
            appsById[c.id] = Self.synthAppInfo(for: c)
        }
        customById = custom
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
        let payload = PersistedLayout(
            order: order,
            folders: Array(folders.values),
            customItems: Array(customById.values)
        )
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
            layout: PersistedLayout(
                order: order,
                folders: Array(folders.values),
                customItems: Array(customById.values)
            ),
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
        // Note: imported custom items (esp. `.script`) are NOT executed on import;
        // they only run when the user clicks them. Their target stays inspectable
        // in the edit sheet and the right-click menu.
        mergeCustomIntoCatalogue(bundle.layout.customItems)
        applyImportedLayout(bundle.layout)
        save()
        currentPage = 0
        clampPage()
    }

    private func applyImportedLayout(_ persisted: PersistedLayout) {
        reconcile(scanned: catalogueSorted(), persisted: persisted)
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

    func launch(_ id: String) {
        if let c = customById[id] { launchCustom(c); dismiss(); return }
        guard let info = appsById[id] else { return }
        NSWorkspace.shared.open(info.url)
        dismiss()
    }

    private func launchCustom(_ c: CustomItem) {
        switch c.kind {
        case .app:
            NSWorkspace.shared.open(URL(fileURLWithPath: c.target))
        case .url:
            if let u = URL(string: c.target.trimmingCharacters(in: .whitespaces)) {
                NSWorkspace.shared.open(u)
            } else { NSSound.beep() }
        case .script:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // -l loads the login profile (PATH like the user's terminal); -c runs the
            // target, which is either a shell-quoted file path or a free command line.
            task.arguments = ["-lc", c.target]
            do { try task.run() } catch { NSSound.beep() }
        }
    }

    func launchFirstResult() {
        guard isSearching, let first = searchResults().first else { return }
        launch(first)
    }

    // MARK: - Custom items (user-added apps / scripts / URLs)

    func isCustom(_ id: String) -> Bool { customById[id] != nil }
    func customItem(_ id: String) -> CustomItem? { customById[id] }

    /// Shell-quote a path so it can be dropped into a `.script` command line safely.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func beginAddItem() { editingItemId = nil; showItemEditor = true }
    func beginEditItem(_ id: String) {
        guard isCustom(id) else { return }
        editingItemId = id
        showItemEditor = true
    }
    func closeItemEditor() { showItemEditor = false; editingItemId = nil }

    @discardableResult
    func addCustomItem(name: String, kind: CustomItemKind, target: String, iconPath: String?) -> Bool {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = "custom-" + UUID().uuidString
        let item = CustomItem(
            id: id,
            name: trimmedName.isEmpty ? Self.defaultName(kind: kind, target: t) : trimmedName,
            kind: kind, target: t,
            iconPath: iconPath?.isEmpty == true ? nil : iconPath
        )
        customById[id] = item
        appsById[id] = Self.synthAppInfo(for: item)
        order.append(id)
        clampPage(); save()
        return true
    }

    @discardableResult
    func updateCustomItem(_ id: String, name: String, kind: CustomItemKind, target: String, iconPath: String?) -> Bool {
        guard isCustom(id) else { return false }
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CustomItem(
            id: id,
            name: trimmedName.isEmpty ? Self.defaultName(kind: kind, target: t) : trimmedName,
            kind: kind, target: t,
            iconPath: iconPath?.isEmpty == true ? nil : iconPath
        )
        customById[id] = item
        appsById[id] = Self.synthAppInfo(for: item)
        objectWillChange.send()
        save()
        return true
    }

    func removeCustomItem(_ id: String) {
        guard isCustom(id) else { return }
        customById[id] = nil
        appsById[id] = nil
        order.removeAll { $0 == id }
        // Pull it out of any folder, dissolving folders that drop below two members.
        for (fid, var f) in folders where f.appIds.contains(id) {
            f.appIds.removeAll { $0 == id }
            if f.appIds.count <= 1 {
                if let leftover = f.appIds.first, let idx = order.firstIndex(of: fid) {
                    order[idx] = leftover
                } else {
                    order.removeAll { $0 == fid }
                }
                folders[fid] = nil
                if openFolderID == fid { openFolderID = nil }
            } else {
                folders[fid] = f
            }
        }
        clampPage(); save()
    }

    private static func defaultName(kind: CustomItemKind, target: String) -> String {
        switch kind {
        case .url:
            return URL(string: target)?.host ?? target
        case .app, .script:
            let last = (target as NSString).lastPathComponent
            return last.isEmpty ? target : ((last as NSString).deletingPathExtension)
        }
    }

    // MARK: - Folder appearance

    func setFolderColor(_ folderId: String, hex: String?) {
        guard var f = folders[folderId] else { return }
        f.colorHex = hex
        folders[folderId] = f
        save()
    }

    // MARK: - Custom-item icon / catalogue synthesis

    /// Build a displayable `AppInfo` (icon + name) for a custom item so the grid,
    /// folders, search, and drag machinery can treat it like any scanned app.
    static func synthAppInfo(for c: CustomItem) -> AppInfo {
        let url: URL
        switch c.kind {
        case .url: url = URL(string: c.target) ?? URL(fileURLWithPath: "/")
        default:   url = URL(fileURLWithPath: c.target)
        }
        return AppInfo(id: c.id, name: c.name, url: url, icon: customIcon(for: c))
    }

    private static func customIcon(for c: CustomItem) -> NSImage {
        if let p = c.iconPath, let img = NSImage(contentsOfFile: p) {
            img.size = NSSize(width: 128, height: 128)
            return img
        }
        switch c.kind {
        case .app, .script:
            // For `.script`, the target may be shell-quoted; strip quotes to probe the path.
            let raw = c.target.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            if FileManager.default.fileExists(atPath: raw) {
                let i = NSWorkspace.shared.icon(forFile: raw)
                i.size = NSSize(width: 128, height: 128)
                return i
            }
            return symbolImage(c.kind == .app ? "app.dashed" : "terminal")
        case .url:
            return symbolImage("safari")
        }
    }

    /// Render an SF Symbol into a white-tinted 128×128 bitmap so it reads on the
    /// dark Launchpad background (template symbols would otherwise draw black).
    private static func symbolImage(_ name: String) -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let out = NSImage(size: size)
        let cfg = NSImage.SymbolConfiguration(pointSize: 84, weight: .regular)
        guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return out }
        out.lockFocus()
        let r = NSRect(
            x: (size.width - sym.size.width) / 2,
            y: (size.height - sym.size.height) / 2,
            width: sym.size.width, height: sym.size.height
        )
        sym.draw(in: r)
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        out.unlockFocus()
        return out
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
