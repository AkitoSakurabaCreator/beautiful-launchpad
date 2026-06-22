import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Add / edit overlay for a user-created launcher item (app / script / URL).
/// Shown when `store.showItemEditor` is true. `store.editingItemId == nil` while
/// adding; non-nil while editing an existing custom item.
struct AddEditItemView: View {
    @EnvironmentObject var store: LaunchpadStore

    @State private var name = ""
    @State private var kind: CustomItemKind = .app
    @State private var target = ""
    @State private var iconPath: String? = nil
    @State private var loaded = false

    private var isEditing: Bool { store.editingItemId != nil }
    private var isGlass: Bool { store.settings.layoutStyle == .glass }
    private var glassTransparency: Double { store.settings.glassTransparency }

    var body: some View {
        ZStack {
            Color.black.opacity(isGlass ? 0.30 : 0.5)
                .opacity(isGlass ? GlassPalette.adjustedOpacity(1, transparency: glassTransparency, reduction: 0.55) : 1)
                .ignoresSafeArea()
                .onTapGesture { store.closeItemEditor() }

            VStack(alignment: .leading, spacing: 16) {
                header

                Picker("", selection: $kind) {
                    Text(store.t(.kindApp)).tag(CustomItemKind.app)
                    Text(store.t(.kindScript)).tag(CustomItemKind.script)
                    Text(store.t(.kindURL)).tag(CustomItemKind.url)
                    Text(store.t(.kindRandomImage)).tag(CustomItemKind.randomImage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                field(store.t(.itemName)) {
                    TextField("", text: $name).textFieldStyle(.roundedBorder)
                }

                field(store.t(.itemTarget)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            TextField(placeholder, text: $target).textFieldStyle(.roundedBorder)
                            if kind != .url {
                                Button(store.t(.chooseFile)) { pickTarget() }
                            }
                        }
                        Text(hint)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                field(store.t(.chooseIcon)) {
                    HStack(spacing: 10) {
                        Button(store.t(.chooseIcon)) { pickIcon() }
                        if let p = iconPath {
                            Text((p as NSString).lastPathComponent)
                                .font(.caption).foregroundColor(.white.opacity(0.55))
                                .lineLimit(1).truncationMode(.middle)
                            Button(store.t(.clearIcon)) { iconPath = nil }
                                .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.2))

                HStack {
                    if isEditing {
                        Button(role: .destructive) {
                            if let id = store.editingItemId { store.removeCustomItem(id) }
                            store.closeItemEditor()
                        } label: {
                            Label(store.t(.deleteItem), systemImage: "trash")
                        }
                    }
                    Spacer()
                    Button(store.t(.cancel)) { store.closeItemEditor() }
                    Button(store.t(.save)) { saveItem() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(26)
            .frame(width: 520)
            .background(panelBackground)
            .foregroundColor(.white)
            .padding(40)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .onAppear(perform: loadIfNeeded)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: isGlass ? 28 : 22, style: .continuous)
            .fill(isGlass ? Color.clear : Color.white.opacity(0.001))
            .background {
                if isGlass {
                    LiquidGlassBackground(
                        shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
                        tint: GlassPalette.coolEdge,
                        transparency: glassTransparency,
                        reduceLiveBlur: store.settings.usesVideoBackground,
                        strokeOpacity: 0.40,
                        shadowOpacity: 0.22
                    )
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: isGlass ? 28 : 22, style: .continuous)
                    .stroke(
                        Color.white.opacity(isGlass
                            ? GlassPalette.adjustedOpacity(0.30, transparency: glassTransparency, reduction: 0.35)
                            : 0.15),
                        lineWidth: 1
                    )
            )
    }

    private var header: some View {
        HStack {
            Text(store.t(isEditing ? .editItem : .addItem))
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Button { store.closeItemEditor() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.7))
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)
            content()
        }
    }

    private var placeholder: String {
        switch kind {
        case .app: return "/Applications/Example.app"
        case .script: return "~/scripts/run.sh   または   say hello"
        case .url: return "https://example.com"
        case .randomImage: return "~/Pictures/Wallpapers"
        }
    }

    private var hint: String {
        switch kind {
        case .app: return store.t(.appHint)
        case .script: return store.t(.scriptHint)
        case .url: return store.t(.urlHint)
        case .randomImage: return store.t(.randomImageHint)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let id = store.editingItemId, let c = store.customItem(id) {
            name = c.name
            kind = c.kind
            target = c.target
            iconPath = c.iconPath
        }
    }

    private func pickTarget() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        // Random-image items target a *folder*; everything else targets a file.
        panel.canChooseDirectories = (kind == .randomImage)
        panel.canChooseFiles = (kind != .randomImage)
        if kind == .app {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Scripts run through a shell, so shell-quote the path (handles spaces).
        target = kind == .script ? LaunchpadStore.shellQuote(url.path) : url.path
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = (url.deletingPathExtension().lastPathComponent)
        }
    }

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        iconPath = url.path
    }

    private func saveItem() {
        let ok: Bool
        if let id = store.editingItemId {
            ok = store.updateCustomItem(id, name: name, kind: kind, target: target, iconPath: iconPath)
        } else {
            ok = store.addCustomItem(name: name, kind: kind, target: target, iconPath: iconPath)
        }
        if ok { store.closeItemEditor() } else { NSSound.beep() }
    }
}
