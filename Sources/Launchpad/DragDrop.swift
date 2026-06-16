import SwiftUI
import UniformTypeIdentifiers

/// One drop delegate per page. Translates pointer movement into reorder previews
/// and folder-merge candidates via the shared geometry maths in `LaunchpadStore`.
struct GridDropDelegate: DropDelegate {
    let store: LaunchpadStore
    let page: Int
    let areaSize: CGSize

    func validateDrop(info: DropInfo) -> Bool { store.isDragging }

    func dropEntered(info: DropInfo) {
        store.updateDragPreview(point: info.location, containerSize: areaSize)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        store.updateDragPreview(point: info.location, containerSize: areaSize)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.commitDrop()
        return true
    }
}

/// Catch-all delegate for drops that land outside any page grid (e.g. on the
/// search bar or page dots). Finalises the in-progress drag instead of leaving
/// the UI stuck mid-drag. Handles either a top-level or a folder-internal drag.
struct RootDropDelegate: DropDelegate {
    let store: LaunchpadStore

    func validateDrop(info: DropInfo) -> Bool { store.isDragging || store.isFolderDragging }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if store.isFolderDragging { store.moveFolderChildOut() } else { store.commitDrop() }
        return true
    }
}

// MARK: - Folder-overlay drop delegates

/// The open-folder card: a single geometry-driven delegate that reorders within the
/// folder and detects nesting into a child folder (mirrors the top-level grid model,
/// which is far more reliable than per-tile drop targets).
struct FolderGridDropDelegate: DropDelegate {
    let store: LaunchpadStore
    let areaSize: CGSize

    func validateDrop(info: DropInfo) -> Bool { store.isFolderDragging }

    func dropEntered(info: DropInfo) {
        store.updateFolderDragPreview(point: info.location, containerSize: areaSize)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        store.updateFolderDragPreview(point: info.location, containerSize: areaSize)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.commitFolderDrop()
        return true
    }
}

/// Backdrop behind the open folder card: dropping here moves the dragged child up
/// one level (out of the folder, into its parent / the top-level grid).
struct FolderMoveOutDropDelegate: DropDelegate {
    let store: LaunchpadStore

    func validateDrop(info: DropInfo) -> Bool { store.isFolderDragging }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        store.moveFolderChildOut()
        return true
    }
}
