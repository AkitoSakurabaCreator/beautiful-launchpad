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
    /// Ids the user has hidden (excluded from grid/folders/search; restorable in Settings).
    @Published var hidden: Set<String> = []
    /// Free-placement coordinates (normalized 0…1 within the page area) keyed by id;
    /// used only when settings.freePlacement is on.
    @Published var freePositions: [String: CGPoint] = [:]
    /// Free-placement page assignment per id (used only in free mode).
    @Published var freePages: [String: Int] = [:]
    /// User-placed widgets (free-positioned & resizable).
    @Published var widgets: [WidgetItem] = []
    /// Last pointer location seen during a drag (page container space) — used to drop
    /// an item at an exact spot in free-placement mode.
    private var lastDragPoint: CGPoint = .zero

    // UI state
    @Published var searchText: String = ""
    @Published var currentPage: Int = 0
    /// Live horizontal offset while a trackpad swipe is in progress (finger-follow
    /// paging); 0 at rest. Committed/snapped on gesture end.
    @Published var pageDragOffset: CGFloat = 0

    /// Open-folder navigation stack (supports nested folders). The last element is
    /// the folder currently shown in the overlay; an empty stack means no overlay.
    @Published var folderPath: [String] = []
    /// Convenience accessor for the folder currently shown (top of the stack).
    var openFolderID: String? { folderPath.last }
    /// Which page of the open folder's contents is visible (folders paginate too).
    @Published var folderPage: Int = 0

    /// Drives the open/close fade + zoom animation (classic Launchpad feel).
    @Published var presented: Bool = false
    private var closing = false

    // Appearance / customization
    @Published var settings = AppSettings()
    @Published var showSettings = false
    /// First-run onboarding / permissions dialog.
    @Published var showOnboarding = false

    /// Custom-item add/edit overlay. `editingItemId == nil` while adding a new one.
    @Published var showItemEditor = false
    @Published var editingItemId: String? = nil

    // Drag state (top-level grid)
    @Published var draggingID: String? = nil
    @Published var dragPreviewOrder: [String]? = nil
    @Published var folderCandidateID: String? = nil
    var isDragging: Bool { draggingID != nil }

    // Folder-internal drag (reorder within / nest into / move out of the open folder).
    // Mirrors the top-level model: a single geometry-based drop delegate drives this.
    @Published var folderDraggingID: String? = nil
    @Published var folderDragPreview: [String]? = nil
    @Published var folderMergeCandidateID: String? = nil
    var isFolderDragging: Bool { folderDraggingID != nil }
    /// Geometry + container size for the open folder's grid, written by the overlay
    /// each layout pass and read by the folder drop delegate (non-published).
    var folderGeo = GridGeometry()
    var folderAreaSize: CGSize = .zero

    /// Called to close/quit the Launchpad (injected by the AppDelegate).
    var onDismiss: (() -> Void)?

    /// Geometry + container size, written by the view each layout pass and read by
    /// the drop delegate. Plain (non-published) to avoid re-render loops.
    var geo = GridGeometry()
    var areaSize: CGSize = .zero

    private var lastFlip = Date.distantPast
    private var lastFolderFlip = Date.distantPast
    private var scrollAccum: CGFloat = 0

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
        // Load hidden ids before reconcile so they are excluded from the layout.
        hidden = Set(persisted?.hidden ?? [])
        freePositions = persisted?.freePositions ?? [:]
        freePages = persisted?.freePages ?? [:]
        widgets = (persisted?.widgets ?? []).map { $0.normalized() }
        reconcile(scanned: catalogueSorted(), persisted: persisted)
        sanitizeFreePlacement()
        clampPage()
        // Show the first-run onboarding / permissions dialog once.
        showOnboarding = !settings.onboardingShown
    }

    /// Number of apps/items currently in the catalogue (shown in onboarding).
    var catalogueCount: Int { appsById.count }

    func dismissOnboarding() {
        updateSettings { $0.onboardingShown = true }
        showOnboarding = false
    }

    /// Open System Settings → Privacy & Security so the user can grant folder access.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
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

    /// Rebuild `folders` + `order` from the persisted layout, supporting nested
    /// folders. Folders are a flat dictionary keyed by id; nesting is expressed by a
    /// folder id appearing inside another folder's `appIds`. Validity is resolved
    /// bottom-up: a folder survives only with ≥2 valid children (an available app or
    /// another valid folder); a lone child bubbles up into its parent; cycles and
    /// stale/duplicate ids are dropped.
    private func reconcile(scanned: [AppInfo], persisted: PersistedLayout?) {
        // Hidden ids are excluded from the layout entirely (they stay in `appsById`
        // so Settings can list and restore them, but never get placed in order/folders).
        let available = Set(scanned.map { $0.id }).subtracting(hidden)
        var pf: [String: Folder] = [:]
        for f in persisted?.folders ?? [] { pf[f.id] = f }

        var rebuilt: [String: Folder] = [:]
        var placed = Set<String>()

        // Returns the ids that should appear in place of `id` in its parent:
        // `[id]` when it stays (app, or folder kept whole), the bubbled children when
        // a folder dissolves to <2, or `[]` when stale / cyclic / already placed.
        func resolve(_ id: String, _ ancestors: Set<String>) -> [String] {
            if placed.contains(id) { return [] }
            if available.contains(id) { placed.insert(id); return [id] }
            guard let f = pf[id], !ancestors.contains(id) else { return [] }
            let anc = ancestors.union([id])
            var children: [String] = []
            for child in f.appIds { children.append(contentsOf: resolve(child, anc)) }
            if children.count >= 2 {
                rebuilt[id] = Folder(id: id, name: f.name, appIds: children, colorHex: f.colorHex)
                placed.insert(id)
                return [id]
            }
            return children   // 0 or 1 leftover bubbles up to the parent
        }

        var newOrder: [String] = []
        if let p = persisted {
            for id in p.order { newOrder.append(contentsOf: resolve(id, [])) }
            // Safety net: rescue any still-valid folder that the saved `order` failed
            // to reference (hand-edited / imported JSON) so its apps don't vanish.
            for fid in pf.keys.sorted() { newOrder.append(contentsOf: resolve(fid, [])) }
        }
        // Append newly discovered apps (alphabetical scan order) not yet placed.
        for a in scanned where !placed.contains(a.id) {
            newOrder.append(a.id)
            placed.insert(a.id)
        }

        folders = rebuilt
        order = newOrder
    }

    // MARK: - Folder tree helpers (nesting-aware)

    /// The folder id that directly contains `childId`, or nil if it lives top-level.
    private func parentFolder(of childId: String) -> String? {
        for (fid, f) in folders where f.appIds.contains(childId) { return fid }
        return nil
    }

    /// True if `descendantId` appears anywhere in the subtree rooted at `ancestorId`.
    /// Used to reject cycles before nesting a folder into one of its own descendants.
    private func folderContains(_ ancestorId: String, _ descendantId: String) -> Bool {
        guard let f = folders[ancestorId] else { return false }
        if f.appIds.contains(descendantId) { return true }
        for child in f.appIds where isFolder(child) {
            if folderContains(child, descendantId) { return true }
        }
        return false
    }

    /// Enforce folder invariants after any mutation: drop stale children, dissolve
    /// folders that fell below two members (their lone child takes the folder's slot
    /// in the parent / top-level), and prune the open-folder navigation path of any
    /// folder that no longer exists or is no longer reachable. Runs to a fixpoint.
    func cleanupFolders() {
        var changed = true
        while changed {
            changed = false
            // 1. Strip children that are neither a live app nor an existing folder.
            for fid in Array(folders.keys) {
                guard var f = folders[fid] else { continue }
                let filtered = f.appIds.filter { isApp($0) || folders[$0] != nil }
                if filtered != f.appIds { f.appIds = filtered; folders[fid] = f; changed = true }
            }
            // 2. Dissolve one undersized folder per pass (bubble its lone child up).
            if let fid = folders.first(where: { $0.value.appIds.count < 2 })?.key {
                let lone = folders[fid]?.appIds.first
                if let parent = parentFolder(of: fid), var p = folders[parent],
                   let idx = p.appIds.firstIndex(of: fid) {
                    if let lone { p.appIds[idx] = lone } else { p.appIds.remove(at: idx) }
                    folders[parent] = p
                } else if let idx = order.firstIndex(of: fid) {
                    if let lone { order[idx] = lone } else { order.remove(at: idx) }
                } else if let lone {
                    order.append(lone)
                }
                folders[fid] = nil
                changed = true
            }
        }

        // Prune the navigation path: each level must still exist and be reachable
        // (level 0 top-level; deeper levels nested inside the previous level).
        var validPath: [String] = []
        for (i, fid) in folderPath.enumerated() {
            guard folders[fid] != nil else { break }
            if i == 0 {
                guard order.contains(fid) else { break }
            } else {
                guard let prev = validPath.last, let p = folders[prev],
                      p.appIds.contains(fid) else { break }
            }
            validPath.append(fid)
        }
        if validPath != folderPath { folderPath = validPath; folderPage = 0 }
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
            customItems: Array(customById.values),
            hidden: Array(hidden),
            freePositions: freePositions,
            freePages: freePages,
            widgets: widgets
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
                customItems: Array(customById.values),
                hidden: Array(hidden),
                freePositions: freePositions,
                freePages: freePages,
                widgets: widgets
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
        hidden = Set(bundle.layout.hidden)
        freePositions = bundle.layout.freePositions
        freePages = bundle.layout.freePages
        widgets = bundle.layout.widgets.map { $0.normalized() }
        applyImportedLayout(bundle.layout)
        sanitizeFreePlacement()
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

    func chooseSlideshowFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings {
            $0.slideshowFolder = url.path
            $0.backgroundKind = .slideshow
        }
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings {
            $0.videoPath = url.path
            $0.videoFolder = nil          // single file overrides the folder playlist
            $0.backgroundKind = .video
        }
    }

    /// Choose a folder of videos played as a playlist (ordered / shuffled).
    func chooseVideoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings {
            $0.videoFolder = url.path
            $0.videoPath = nil            // folder playlist overrides a single file
            $0.backgroundKind = .video
        }
    }

    // MARK: - Per-page background overrides

    func pageHasBackground(_ page: Int) -> Bool { settings.pageBackgrounds["\(page)"] != nil }

    func setPageBackgroundColor(_ page: Int, hex: String) {
        updateSettings { $0.pageBackgrounds["\(page)"] = PageBackground(kind: .color, colorHex: hex, imagePath: nil) }
    }

    func setPageBackgroundImage(_ page: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings { $0.pageBackgrounds["\(page)"] = PageBackground(kind: .image, colorHex: nil, imagePath: url.path) }
    }

    func clearPageBackground(_ page: Int) {
        updateSettings { $0.pageBackgrounds["\(page)"] = nil }
    }

    // MARK: - Derived data

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func searchResults() -> [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return appsById.values
            .filter { !hidden.contains($0.id) && $0.name.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { $0.id }
    }

    /// The list rendered at the top level (uses the live drag preview while dragging).
    func topLevelTiles() -> [String] {
        if isDragging, let preview = dragPreviewOrder { return preview }
        return order
    }

    func pages(geo: GridGeometry) -> [[String]] {
        if isSearching { return chunk(searchResults(), geo.pageSize) }
        let items = topLevelTiles()
        if settings.freePlacement { return freeModePages(items, geo: geo) }
        return chunk(items, geo.pageSize)
    }

    /// In free-placement mode, group items by their assigned page (explicit free page,
    /// else their natural grid page) and always append one spare empty page at the end
    /// so an item can be dragged onto a brand-new page.
    private func freeModePages(_ items: [String], geo: GridGeometry) -> [[String]] {
        let size = max(1, geo.pageSize)
        func pageOf(_ id: String, _ idx: Int) -> Int {
            min(max(freePages[id] ?? (idx / size), 0), Self.maxFreePage)
        }
        var maxPage = 0
        for (i, id) in items.enumerated() { maxPage = max(maxPage, pageOf(id, i)) }
        let count = min(maxPage + 2, Self.maxFreePage + 2)   // +1 used range, +1 spare; capped
        var result = Array(repeating: [String](), count: count)
        for (i, id) in items.enumerated() {
            let p = min(max(0, pageOf(id, i)), count - 1)
            result[p].append(id)
        }
        return result
    }

    func clampPage() {
        let count = pages(geo: geo).count
        currentPage = min(max(0, currentPage), max(0, count - 1))
    }

    // MARK: - Actions

    func launch(_ id: String) {
        playLaunchSound()
        if let c = customById[id] { launchCustom(c); dismiss(); return }
        guard let info = appsById[id] else { return }
        NSWorkspace.shared.open(info.url)
        dismiss()
    }

    /// Built-in macOS system sounds offered for the launch sound.
    static let availableSounds = ["Pop", "Tink", "Glass", "Hero", "Submarine", "Ping", "Funk", "Morse"]

    /// Play the configured launch sound, if enabled. Played via a detached `afplay`
    /// process so it keeps sounding even though the Launchpad terminates itself
    /// immediately after launching the target (an in-process NSSound would be cut).
    /// A user-chosen custom sound file takes precedence over the built-in presets.
    private func playLaunchSound() {
        guard settings.launchSound else { return }
        let path: String
        if let custom = settings.launchSoundPath, FileManager.default.fileExists(atPath: custom) {
            path = custom
        } else {
            // Validate the preset name against the known list (an imported settings file
            // could carry an arbitrary string); fall back to a safe default.
            let name = Self.availableSounds.contains(settings.launchSoundName) ? settings.launchSoundName : "Pop"
            path = "/System/Library/Sounds/\(name).aiff"
        }
        guard FileManager.default.fileExists(atPath: path) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = [path]
        try? p.run()
    }

    /// Pick a custom sound file (mp3/wav/aiff/m4a/caf) for the launch sound.
    func chooseLaunchSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateSettings {
            $0.launchSoundPath = url.path
            $0.launchSound = true
        }
        // Preview the chosen sound once.
        playLaunchSound()
    }

    /// Revert to the built-in preset launch sound.
    func clearLaunchSound() {
        updateSettings { $0.launchSoundPath = nil }
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
        case .randomImage:
            let folder = c.target.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            if let pick = imageFiles(in: folder).randomElement() {
                NSWorkspace.shared.open(URL(fileURLWithPath: pick))
            } else { NSSound.beep() }
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
        // Pull it out of any folder; cleanupFolders dissolves any that fall below two.
        for fid in Array(folders.keys) where folders[fid]?.appIds.contains(id) == true {
            folders[fid]?.appIds.removeAll { $0 == id }
        }
        cleanupFolders()
        clampPage(); save()
    }

    private static func defaultName(kind: CustomItemKind, target: String) -> String {
        switch kind {
        case .url:
            return URL(string: target)?.host ?? target
        case .app, .script, .randomImage:
            let last = (target as NSString).lastPathComponent
            return last.isEmpty ? target : ((last as NSString).deletingPathExtension)
        }
    }

    // MARK: - Hide / unhide

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    /// Hide an app / custom item: remove it from the grid and any folder, and remember
    /// the choice so a rescan won't re-add it. Folders themselves are not hideable.
    func hide(_ id: String) {
        guard isApp(id), !isFolder(id), !hidden.contains(id) else { return }
        hidden.insert(id)
        order.removeAll { $0 == id }
        for fid in Array(folders.keys) where folders[fid]?.appIds.contains(id) == true {
            folders[fid]?.appIds.removeAll { $0 == id }
        }
        cleanupFolders()
        clampPage()
        save()
    }

    /// Restore a previously hidden item back onto the top-level grid.
    func unhide(_ id: String) {
        guard hidden.contains(id) else { return }
        hidden.remove(id)
        // Re-place it on the grid if it still exists and isn't already somewhere.
        if isApp(id), !order.contains(id), parentFolder(of: id) == nil {
            order.append(id)
        }
        clampPage()
        save()
    }

    /// Hidden items that still resolve to a catalogue entry, sorted by name (for Settings).
    func hiddenItems() -> [AppInfo] {
        hidden.compactMap { appsById[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        case .randomImage:
            return symbolImage("photo.on.rectangle.angled")
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
        let closeAnim = settings.openAnim
        withAnimation(closeAnim) { presented = false }
        let delay = closeAnim == nil ? 0.0 : settings.openCloseDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.02) { [weak self] in
            self?.onDismiss?()
        }
    }

    func escape() {
        if showSettings { showSettings = false; return }
        if !folderPath.isEmpty { closeFolder(); return }   // pop one nested level
        if isSearching { searchText = ""; currentPage = 0; return }
        dismiss()
    }

    func backgroundTap() {
        if !folderPath.isEmpty { closeAllFolders(); return }
        dismiss()
    }

    // MARK: - Folder navigation (nested-folder aware)

    /// Push a folder onto the navigation stack (open it / drill into a sub-folder).
    func openFolder(_ id: String) {
        guard isFolder(id) else { return }
        folderPath.append(id)
        folderPage = 0
    }

    /// Pop one level (back out of a nested folder, or close the top-level folder).
    func closeFolder() {
        if !folderPath.isEmpty { folderPath.removeLast() }
        folderPage = 0
    }

    /// Close the folder overlay entirely (all nested levels).
    func closeAllFolders() {
        folderPath.removeAll()
        folderPage = 0
    }

    func nextPage() {
        // When a folder is open, paging targets the folder's contents instead.
        if !folderPath.isEmpty { folderNextPage(); return }
        let count = pages(geo: geo).count
        if currentPage < count - 1 { withAnimation(settings.spring(0.4)) { currentPage += 1 } }
    }

    func prevPage() {
        if !folderPath.isEmpty { folderPrevPage(); return }
        if currentPage > 0 { withAnimation(settings.spring(0.4)) { currentPage -= 1 } }
    }

    /// Jump to a specific top-level page (page-dot taps), animated.
    func goToPage(_ i: Int) {
        withAnimation(settings.spring(0.4)) { currentPage = i }
    }

    func folderNextPage() {
        let count = folderPages().count
        if folderPage < count - 1 { folderPage += 1 }
    }

    func folderPrevPage() {
        if folderPage > 0 { folderPage -= 1 }
    }

    /// Page navigation from scroll/swipe.
    ///
    /// Trackpad swipes are now *interactive*: the page tracks the fingers in real
    /// time (`pageDragOffset`) and only commits to the next/previous page on release
    /// if dragged past a distance threshold — otherwise it springs back. This fixes
    /// the old behaviour where a partial swipe could jump a page without following
    /// the cursor. Mouse wheels (no phase info) keep a debounced discrete flip.
    func handleScrollEvent(deltaX: CGFloat,
                           deltaY: CGFloat,
                           phase: NSEvent.Phase,
                           momentum: NSEvent.Phase,
                           precise: Bool) {
        guard !showSettings else { return }

        // Folder open → discrete flip of the folder's own pages (no finger-follow).
        if !folderPath.isEmpty {
            if !momentum.isEmpty { return }
            let now = Date()
            guard now.timeIntervalSince(lastFlip) > 0.4 else { return }
            let d = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
            if d < -1 { lastFlip = now; folderNextPage() }
            else if d > 1 { lastFlip = now; folderPrevPage() }
            return
        }

        if precise && !phase.isEmpty {
            if !momentum.isEmpty { return }   // ignore inertial tail
            let width = areaSize.width
            if phase.contains(.began) {
                scrollAccum = 0
                pageDragOffset = 0
            }
            if phase.contains(.changed) {
                if abs(deltaX) >= abs(deltaY) { scrollAccum += deltaX }
                pageDragOffset = rubberBanded(scrollAccum, width: width)
            }
            if phase.contains(.ended) || phase.contains(.cancelled) {
                let count = pages(geo: geo).count
                let threshold = max(60, width * 0.16)
                var target = currentPage
                if scrollAccum <= -threshold, currentPage < count - 1 { target += 1 }
                else if scrollAccum >= threshold, currentPage > 0 { target -= 1 }
                scrollAccum = 0
                withAnimation(settings.spring(0.4)) {
                    currentPage = target
                    pageDragOffset = 0
                }
            }
        } else {
            // Classic mouse wheel (no phase info): debounced discrete flip.
            if !momentum.isEmpty { return }
            let now = Date()
            guard now.timeIntervalSince(lastFlip) > 0.45 else { return }
            let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
            if delta < -1 { lastFlip = now; nextPage() }
            else if delta > 1 { lastFlip = now; prevPage() }
        }
    }

    /// Apply edge resistance so swiping past the first/last page rubber-bands.
    private func rubberBanded(_ accum: CGFloat, width: CGFloat) -> CGFloat {
        let count = pages(geo: geo).count
        if currentPage == 0 && accum > 0 { return accum * 0.35 }
        if currentPage >= count - 1 && accum < 0 { return accum * 0.35 }
        return accum
    }

    // MARK: - Folder mutations

    func defaultFolderName() -> String { t(.folderDefaultName) }

    /// Wrap two top-level items into a new folder occupying `keepId`'s slot.
    /// `addId` may itself be a folder (dragging a folder onto an app → nesting).
    func createFolder(keep keepId: String, add addId: String) {
        guard keepId != addId else { return }
        let fid = "folder-" + UUID().uuidString
        folders[fid] = Folder(id: fid, name: defaultFolderName(), appIds: [keepId, addId])
        var o = order
        if let idx = o.firstIndex(of: keepId) { o[idx] = fid } else { o.append(fid) }
        o.removeAll { $0 == addId }
        order = o
        cleanupFolders(); save()
    }

    /// Move a top-level / nested item (app OR folder) into `folderId`. Rejects cycles
    /// (a folder cannot be nested into one of its own descendants).
    func addToFolder(child childId: String, folderId: String) {
        guard var f = folders[folderId], childId != folderId else { return }
        if isFolder(childId), folderContains(childId, folderId) { return }
        // Detach from wherever it currently lives (top-level or another folder).
        order.removeAll { $0 == childId }
        for fid in Array(folders.keys) where fid != folderId {
            folders[fid]?.appIds.removeAll { $0 == childId }
        }
        if !f.appIds.contains(childId) { f.appIds.append(childId) }
        folders[folderId] = f
        cleanupFolders(); save()
    }

    /// Create a new sub-folder *inside the currently open folder* from two of its
    /// app children (drag one app onto another while a folder is open).
    func createFolderInsideCurrent(keep keepId: String, add addId: String) {
        guard let parent = folderPath.last, var pf = folders[parent],
              keepId != addId, isApp(keepId), isApp(addId) else { return }
        let fid = "folder-" + UUID().uuidString
        folders[fid] = Folder(id: fid, name: defaultFolderName(), appIds: [keepId, addId])
        if let idx = pf.appIds.firstIndex(of: keepId) { pf.appIds[idx] = fid } else { pf.appIds.append(fid) }
        pf.appIds.removeAll { $0 == addId }
        folders[parent] = pf
        cleanupFolders(); clampFolderPage(); save()
    }

    /// Pull a child out of `folderId` back to its parent folder (one level up) or to
    /// the top-level grid, placed right after the folder. cleanupFolders dissolves
    /// the folder if it falls below two members.
    func removeFromFolder(_ childId: String, _ folderId: String) {
        guard folders[folderId] != nil else { return }
        folders[folderId]?.appIds.removeAll { $0 == childId }
        if let parent = parentFolder(of: folderId), var pf = folders[parent],
           let idx = pf.appIds.firstIndex(of: folderId) {
            pf.appIds.insert(childId, at: min(idx + 1, pf.appIds.count))
            folders[parent] = pf
        } else if let idx = order.firstIndex(of: folderId) {
            order.insert(childId, at: min(idx + 1, order.count))
        } else {
            order.append(childId)
        }
        cleanupFolders(); clampPage(); save()
    }

    func renameFolder(_ folderId: String, _ name: String) {
        guard var f = folders[folderId] else { return }
        f.name = name
        folders[folderId] = f
        save()
    }

    // MARK: - Folder-internal drag (reorder / nest / move out of the open folder)

    /// Children of the open folder, using the live drag preview while reordering.
    func folderTiles() -> [String] {
        guard let fid = folderPath.last, let f = folders[fid] else { return [] }
        if isFolderDragging, let p = folderDragPreview { return p }
        return f.appIds
    }

    /// The open folder's children split into pages (folders paginate like the grid).
    func folderPages() -> [[String]] { chunk(folderTiles(), folderGeo.pageSize) }

    func clampFolderPage() {
        let count = max(1, folderPages().count)
        folderPage = min(max(0, folderPage), count - 1)
    }

    func beginFolderDrag(_ id: String) {
        guard !isSearching, let fid = folderPath.last, let f = folders[fid] else { return }
        folderDraggingID = id
        folderDragPreview = f.appIds
        folderMergeCandidateID = nil
    }

    private func endFolderDragReset() {
        folderDraggingID = nil
        folderDragPreview = nil
        folderMergeCandidateID = nil
    }

    func cancelFolderDrag() { endFolderDragReset() }

    /// Reorder / nest preview from the pointer location (open-folder card space).
    func updateFolderDragPreview(point: CGPoint, containerSize: CGSize) {
        guard let dragging = folderDraggingID, let fid = folderPath.last,
              let f = folders[fid] else { return }

        // Edge zones flip folder pages mid-drag (drag an item to the next page).
        let edge: CGFloat = 52
        if point.x < edge {
            flipFolder(next: false)
        } else if point.x > containerSize.width - edge {
            flipFolder(next: true)
        }

        let g = folderGeo
        let working = f.appIds.filter { $0 != dragging }
        let size = g.pageSize
        let pagesW = chunk(working, size)
        let page = min(max(0, folderPage), max(0, pagesW.count - 1))
        let pageItems = pagesW.indices.contains(page) ? pagesW[page] : []

        let stepX = g.cellWidth + g.hSpacing
        let stepY = g.cellHeight + g.vSpacing
        var col = Int(floor((point.x - g.leftPad) / max(1, stepX)))
        var row = Int(floor((point.y - g.topPad) / max(1, stepY)))
        col = min(max(col, 0), g.columns - 1)
        row = min(max(row, 0), g.rows - 1)
        let cellIndex = row * g.columns + col

        // Merge candidate: hovering the centre of another child.
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
                let canMerge: Bool
                if isApp(dragging) {
                    canMerge = isApp(hoveredId) || isFolder(hoveredId)       // new sub-folder / nest deeper
                } else if isFolder(dragging) {
                    canMerge = isFolder(hoveredId) && !folderContains(dragging, hoveredId)
                } else {
                    canMerge = false
                }
                if inInner && canMerge {
                    folderMergeCandidateID = hoveredId
                    folderDragPreview = f.appIds
                    return
                }
            }
        }

        // Otherwise reorder: compute the insertion index within the page.
        folderMergeCandidateID = nil
        var localInsert = cellIndex
        let cellLeft = g.leftPad + CGFloat(col) * stepX
        if point.x > cellLeft + g.cellWidth / 2 { localInsert = cellIndex + 1 }
        localInsert = min(localInsert, pageItems.count)
        let globalInsert = min(page * size + localInsert, working.count)

        var preview = working
        preview.insert(dragging, at: globalInsert)
        folderDragPreview = preview
    }

    /// Drop landed inside the open folder card → reorder, or nest into a child.
    func commitFolderDrop() {
        defer { endFolderDragReset(); clampFolderPage() }
        guard let dragging = folderDraggingID, let parent = folderPath.last,
              var pf = folders[parent] else { return }

        if let target = folderMergeCandidateID, target != dragging {
            if isFolder(target) {
                addToFolder(child: dragging, folderId: target)   // nest into a child folder
                return
            } else if isApp(target), isApp(dragging) {
                createFolderInsideCurrent(keep: target, add: dragging)
                return
            }
        }
        if let preview = folderDragPreview {
            pf.appIds = preview
            folders[parent] = pf
        }
        cleanupFolders(); save()
    }

    /// Drop landed outside the open folder card → move the child up one level
    /// (into the parent folder, or to the top-level grid).
    func moveFolderChildOut() {
        defer { endFolderDragReset() }
        guard let dragging = folderDraggingID, let current = folderPath.last,
              folders[current] != nil else { return }
        removeFromFolder(dragging, current)
    }

    private func flipFolder(next: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastFolderFlip) > 0.6 else { return }
        guard let fid = folderPath.last, let f = folders[fid] else { return }
        let count = chunk(f.appIds, folderGeo.pageSize).count
        if next {
            if folderPage < count - 1 { folderPage += 1; lastFolderFlip = now }
        } else {
            if folderPage > 0 { folderPage -= 1; lastFolderFlip = now }
        }
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
        lastDragPoint = point

        // Free-placement mode: no reorder/merge preview — the item simply lands where
        // it is dropped (handled in commitDrop). Edge zones still flip pages so an item
        // can be carried to another (or a new) page.
        if settings.freePlacement {
            let fe: CGFloat = 70
            if point.x < fe { flip(next: false) }
            else if point.x > containerSize.width - fe { flip(next: true) }
            folderCandidateID = nil
            dragPreviewOrder = order
            return
        }

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
                // App → app (create folder) / app → folder (add) / folder → folder
                // (nest). A folder dropped on a plain app just reorders.
                let canMerge: Bool
                if isApp(dragging) {
                    canMerge = isApp(hoveredId) || isFolder(hoveredId)
                } else if isFolder(dragging) {
                    canMerge = isFolder(hoveredId) && !folderContains(dragging, hoveredId)
                } else {
                    canMerge = false
                }
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

        // Free placement: store the dropped position (normalized) + the page it landed
        // on (the user may have carried it to another / a new page mid-drag).
        if settings.freePlacement {
            setFreePosition(dragging, point: lastDragPoint, container: areaSize)
            freePages[dragging] = min(max(currentPage, 0), Self.maxFreePage)
            endDragReset()
            clampPage()
            save()
            return
        }

        if let target = folderCandidateID, target != dragging {
            if isFolder(target) {
                addToFolder(child: dragging, folderId: target)   // app or folder → folder
            } else if isApp(target), isApp(dragging) {
                createFolder(keep: target, add: dragging)
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

    // MARK: - Free placement

    /// Store a normalized (0…1) free position for `id` from a drop point in page space.
    func setFreePosition(_ id: String, point: CGPoint, container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        let x = min(max(point.x / container.width, 0), 1)
        let y = min(max(point.y / container.height, 0), 1)
        freePositions[id] = CGPoint(x: x, y: y)
    }

    /// Where a tile should be drawn: its free position (free-placement mode) or its
    /// natural grid-slot centre.
    func tilePosition(for id: String, index: Int, geo: GridGeometry, area: CGSize) -> CGPoint {
        if settings.freePlacement, let p = freePositions[id] {
            return CGPoint(x: p.x * area.width, y: p.y * area.height)
        }
        return geo.cellCenter(forIndex: index)
    }

    /// Drop all free positions/pages and return to the auto-aligned grid.
    func realignToGrid() {
        freePositions.removeAll()
        freePages.removeAll()
        clampPage()
        save()
    }

    /// Upper bound on free-placement page index (defense against a hand-edited /
    /// imported file inflating `freeModePages`'s `maxPage + 2` allocation).
    static let maxFreePage = 63

    /// Prune free-placement data to live ids and clamp coordinates/pages into range so
    /// an untrusted layout file can't cause off-screen icons or a huge allocation.
    private func sanitizeFreePlacement() {
        let valid = Set(order)
        freePositions = freePositions
            .filter { valid.contains($0.key) }
            .mapValues { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        freePages = freePages
            .filter { valid.contains($0.key) }
            .mapValues { min(max($0, 0), Self.maxFreePage) }
    }

    // MARK: - Widgets (free-positioned & resizable)

    func widgetsOnPage(_ page: Int) -> [WidgetItem] { widgets.filter { $0.page == page } }
    func widget(_ id: String) -> WidgetItem? { widgets.first { $0.id == id } }

    /// Add a widget to the centre-ish of the given page.
    func addWidget(_ kind: WidgetKind, page: Int) {
        var w = WidgetItem(id: "widget-" + UUID().uuidString, kind: kind, page: page)
        // Default size by kind (normalized).
        switch kind {
        case .notes:   w.w = 0.26; w.h = 0.22
        case .weather: w.w = 0.24; w.h = 0.18
        default:       w.w = 0.20; w.h = 0.15
        }
        // Slight cascade so multiple new widgets don't stack exactly.
        let n = Double(widgetsOnPage(page).count % 5)
        w.x = min(0.85, 0.3 + n * 0.06)
        w.y = min(0.85, 0.35 + n * 0.05)
        widgets.append(w.normalized())
        save()
    }

    func removeWidget(_ id: String) {
        widgets.removeAll { $0.id == id }
        save()
    }

    func updateWidgetText(_ id: String, _ text: String) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].text = text
        save()
    }

    /// Move a widget to a normalized centre derived from a drop point in page space.
    func moveWidget(_ id: String, center: CGPoint, container: CGSize) {
        guard container.width > 0, container.height > 0,
              let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].x = min(max(center.x / container.width, 0), 1)
        widgets[i].y = min(max(center.y / container.height, 0), 1)
        widgets[i] = widgets[i].normalized()
        save()
    }

    /// Resize a widget to a normalized size derived from a pixel size in page space.
    func resizeWidget(_ id: String, size: CGSize, container: CGSize) {
        guard container.width > 0, container.height > 0,
              let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].w = min(max(size.width / container.width, 0.08), 0.9)
        widgets[i].h = min(max(size.height / container.height, 0.06), 0.9)
        save()
    }

    private func flip(next: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastFlip) > 0.6 else { return }
        // Use the live page count (free mode adds a spare trailing page to flip onto).
        let count = pages(geo: geo).count
        if next {
            if currentPage < count - 1 { currentPage += 1; lastFlip = now }
        } else {
            if currentPage > 0 { currentPage -= 1; lastFlip = now }
        }
    }
}
