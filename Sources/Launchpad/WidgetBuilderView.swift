import SwiftUI
import AppKit

/// Create / edit a user-defined declarative widget (Phase 1: static text / SF Symbol /
/// local image). Shown when `store.showWidgetBuilder` is true; `store.editingWidgetDefId`
/// is nil while creating, non-nil while editing an existing definition.
///
/// The produced widget is pure data (a `WidgetDefinition` layout tree) — no code runs —
/// so definitions are safe to share and to import on another machine.
struct WidgetBuilderView: View {
    @EnvironmentObject var store: LaunchpadStore

    @State private var name = ""
    @State private var symbol = ""
    @State private var headline = ""
    @State private var subtitle = ""
    @State private var accentHex = ""
    @State private var imagePath: String? = nil
    @State private var loaded = false

    private var isEditing: Bool { store.editingWidgetDefId != nil }
    private var isGlass: Bool { store.settings.layoutStyle == .glass }
    private var glassTransparency: Double { store.settings.glassTransparency }

    /// Accent swatches; first entry (empty hex) = theme default.
    private let accentPalette: [(name: String, hex: String)] = [
        ("Cyan", "#00F0FF"), ("Blue", "#2563EB"), ("Purple", "#7C3AED"),
        ("Pink", "#FF2D95"), ("Amber", "#F59E0B"), ("Green", "#10B981"),
        ("Rose", "#F43F5E"), ("White", "#FFFFFF"),
    ]

    private var isEmptyDefinition: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        headline.trimmingCharacters(in: .whitespaces).isEmpty &&
        subtitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        (imagePath?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isGlass ? 0.30 : 0.5)
                .opacity(isGlass ? GlassPalette.adjustedOpacity(1, transparency: glassTransparency, reduction: 0.55) : 1)
                .ignoresSafeArea()
                .onTapGesture { store.closeWidgetBuilder() }

            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        field(store.t(.builderName)) {
                            TextField("", text: $name).textFieldStyle(.roundedBorder)
                        }
                        field(store.t(.builderSymbol)) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("star.fill", text: $symbol).textFieldStyle(.roundedBorder)
                                Text(store.t(.builderSymbolHint))
                                    .font(.caption).foregroundColor(.white.opacity(0.5))
                            }
                        }
                        field(store.t(.builderHeadline)) {
                            TextField("", text: $headline).textFieldStyle(.roundedBorder)
                        }
                        field(store.t(.builderSubtitle)) {
                            TextField("", text: $subtitle).textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(width: 280)

                    preview
                }

                field(store.t(.builderAccent)) { accentRow }

                field(store.t(.builderImage)) {
                    HStack(spacing: 10) {
                        Button(store.t(.chooseFile)) { pickImage() }
                        if let p = imagePath, !p.isEmpty {
                            Text((p as NSString).lastPathComponent)
                                .font(.caption).foregroundColor(.white.opacity(0.55))
                                .lineLimit(1).truncationMode(.middle)
                            Button(store.t(.clearIcon)) { imagePath = nil }
                                .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.2))

                HStack {
                    if isEditing {
                        Button(role: .destructive) {
                            if let id = store.editingWidgetDefId { store.deleteWidgetDefinition(id) }
                            store.closeWidgetBuilder()
                        } label: {
                            Label(store.t(.deleteItem), systemImage: "trash")
                        }
                    }
                    Spacer()
                    Button(store.t(.cancel)) { store.closeWidgetBuilder() }
                    Button(store.t(.save)) { saveDefinition() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isEmptyDefinition)
                }
            }
            .padding(26)
            .frame(width: 620)
            .background(panelBackground)
            .foregroundColor(.white)
            .padding(40)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text(store.t(.builderTitle)).font(.title2).bold()
            Spacer()
        }
    }

    private var preview: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1))
                DeclarativeWidgetView(node: previewNode, accent: previewAccent)
            }
            .frame(width: 200, height: 150)
        }
    }

    private var accentRow: some View {
        HStack(spacing: 8) {
            swatch(hex: "", label: store.t(.builderAccentDefault))
            ForEach(accentPalette, id: \.hex) { c in swatch(hex: c.hex, label: c.name) }
        }
    }

    private func swatch(hex: String, label: String) -> some View {
        let selected = accentHex == hex
        return Button {
            accentHex = hex
        } label: {
            Circle()
                .fill(hex.isEmpty ? Color.white.opacity(0.18) : Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().stroke(Color.white.opacity(selected ? 0.95 : 0.25),
                                    lineWidth: selected ? 2.5 : 1)
                )
                .overlay(
                    hex.isEmpty
                        ? AnyView(Image(systemName: "slash.circle").font(.system(size: 11)).foregroundColor(.white.opacity(0.7)))
                        : AnyView(EmptyView())
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.6))
            content()
        }
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

    // MARK: - Preview model

    private var previewAccent: Color { accentHex.isEmpty ? .white : Color(hex: accentHex) }

    private var previewNode: WidgetNode {
        let sym = symbol.trimmingCharacters(in: .whitespaces)
        let ttl = headline.trimmingCharacters(in: .whitespaces)
        let sub = subtitle.trimmingCharacters(in: .whitespaces)
        var children: [WidgetNode] = []
        if !sym.isEmpty { children.append(WidgetNode(type: .symbol, value: sym, size: 30)) }
        if let p = imagePath, !p.trimmingCharacters(in: .whitespaces).isEmpty {
            children.append(WidgetNode(type: .image, value: p))
        }
        if !ttl.isEmpty { children.append(WidgetNode(type: .text, value: ttl, size: 20, weight: "bold")) }
        if !sub.isEmpty { children.append(WidgetNode(type: .text, value: sub, size: 13)) }
        if children.isEmpty {
            let n = name.trimmingCharacters(in: .whitespaces)
            children.append(WidgetNode(type: .text, value: n.isEmpty ? "Widget" : n, size: 18, weight: "semibold"))
        }
        return WidgetNode(type: .vstack, children: children)
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let id = store.editingWidgetDefId, let def = store.widgetDefinition(id) else { return }
        name = def.name
        accentHex = def.accent
        guard let layout = def.layout else { return }
        for c in layout.children {
            switch c.type {
            case .symbol: if symbol.isEmpty { symbol = c.value }
            case .image:  if imagePath == nil { imagePath = c.value }
            case .text:
                if headline.isEmpty && (c.weight == "bold" || c.size >= 18) { headline = c.value }
                else if subtitle.isEmpty { subtitle = c.value }
            default: break
            }
        }
    }

    private func saveDefinition() {
        if isEditing, let id = store.editingWidgetDefId {
            store.updateWidgetDefinition(id, name: name, symbol: symbol, title: headline,
                                         subtitle: subtitle, accentHex: accentHex, imagePath: imagePath)
        } else {
            store.createWidgetDefinition(name: name, symbol: symbol, title: headline,
                                         subtitle: subtitle, accentHex: accentHex, imagePath: imagePath)
        }
        store.closeWidgetBuilder()
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { imagePath = url.path }
    }
}
