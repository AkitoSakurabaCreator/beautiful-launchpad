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
/// the UI stuck mid-drag.
struct RootDropDelegate: DropDelegate {
    let store: LaunchpadStore

    func validateDrop(info: DropInfo) -> Bool { store.isDragging }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.commitDrop()
        return true
    }
}

// MARK: - Folder-overlay drop delegates

/// Backdrop behind the open folder: dropping an app here pulls it out of the folder.
struct FolderRemoveDropDelegate: DropDelegate {
    let store: LaunchpadStore

    func validateDrop(info: DropInfo) -> Bool { store.folderDragApp != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        store.dropFolderAppOut()
        return true
    }
}

/// The folder panel's empty area: dropping here keeps the app in the folder.
struct FolderKeepDropDelegate: DropDelegate {
    let store: LaunchpadStore

    func validateDrop(info: DropInfo) -> Bool { store.folderDragApp != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        store.endFolderDrag()
        return true
    }
}

/// An app tile inside the folder: dropping onto it reorders within the folder.
struct FolderReorderDropDelegate: DropDelegate {
    let store: LaunchpadStore
    let targetId: String

    func validateDrop(info: DropInfo) -> Bool { store.folderDragApp != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        store.reorderInFolder(before: targetId)
        return true
    }
}
