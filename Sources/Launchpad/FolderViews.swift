import SwiftUI
import UniformTypeIdentifiers

/// Full-screen overlay shown when a folder is opened: editable name + grid of
/// contained apps. Click an app to launch; the − button removes it; or drag an
/// app out of the panel to move it back to the home grid (drag onto another app
/// to reorder within the folder).
struct FolderOverlayView: View {
    @EnvironmentObject var store: LaunchpadStore
    let folder: Folder
    @State private var hoveredRemove: String? = nil

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 24), count: 5)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.openFolderID = nil }
                // Dropping a folder app onto the backdrop pulls it out of the folder.
                .onDrop(of: [UTType.text], delegate: FolderRemoveDropDelegate(store: store))

            VStack(spacing: 22) {
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

                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(store.folder(folder.id)?.appIds ?? [], id: \.self) { appId in
                        if let app = store.app(appId) {
                            ZStack(alignment: .topTrailing) {
                                AppIconView(app: app, iconSize: 74)
                                    .onTapGesture { store.launch(appId) }

                                Button {
                                    store.removeFromFolder(appId, folder.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .opacity(hoveredRemove == appId ? 1 : 0.0)
                                .offset(x: 6, y: -4)
                            }
                            .onHover { hoveredRemove = $0 ? appId : nil }
                            .onDrag {
                                store.beginFolderDrag(appId, folderId: folder.id)
                                return NSItemProvider(object: appId as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: FolderReorderDropDelegate(store: store, targetId: appId)
                            )
                        }
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 760)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            // Dropping in the panel's empty area keeps the app inside the folder.
            .onDrop(of: [UTType.text], delegate: FolderKeepDropDelegate(store: store))
            .padding(40)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}
