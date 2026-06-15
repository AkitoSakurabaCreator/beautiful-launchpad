import SwiftUI

/// Customization panel: background (desktop blur / theme / image / solid),
/// grid density, dim, labels, plus config export/import.
struct SettingsView: View {
    @EnvironmentObject var store: LaunchpadStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { store.showSettings = false }

            VStack(alignment: .leading, spacing: 18) {
                header

                backgroundSection

                Divider().overlay(Color.white.opacity(0.2))

                gridSection

                Divider().overlay(Color.white.opacity(0.2))

                transferSection
            }
            .padding(28)
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(40)
            .foregroundColor(.white)
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("カスタマイズ").font(.system(size: 22, weight: .bold))
            Spacer()
            Button { store.showSettings = false } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.7))
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("背景").font(.headline)
            Picker("背景", selection: bindingKind) {
                Text("デスクトップぼかし").tag(BackgroundKind.desktopBlur)
                Text("テーマ").tag(BackgroundKind.theme)
                Text("画像").tag(BackgroundKind.image)
                Text("単色").tag(BackgroundKind.solid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch store.settings.backgroundKind {
            case .theme:
                themeSwatches
            case .image:
                HStack(spacing: 12) {
                    Button("画像を選択…") { store.chooseWallpaper() }
                    if let p = store.settings.wallpaperPath {
                        Text((p as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            case .solid:
                ColorPicker("色", selection: bindingSolidColor, supportsOpacity: false)
                    .frame(maxWidth: 160)
            case .desktopBlur:
                Text("デスクトップを背景にぼかして表示します。")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack {
                Text("暗さ").frame(width: 40, alignment: .leading)
                Slider(value: bindingDim, in: 0...0.6)
            }
        }
    }

    private var themeSwatches: some View {
        HStack(spacing: 12) {
            ForEach(Theming.themes) { theme in
                let selected = store.settings.themeIndex == theme.id
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: theme.colors,
                                         startPoint: theme.start, endPoint: theme.end))
                    .frame(width: 64, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(selected ? 0.95 : 0.2),
                                    lineWidth: selected ? 3 : 1)
                    )
                    .onTapGesture {
                        store.updateSettings {
                            $0.themeIndex = theme.id
                            $0.backgroundKind = .theme
                        }
                    }
            }
        }
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("レイアウト").font(.headline)
            Stepper("列数: \(store.settings.columns)", value: bindingColumns, in: 4...10)
            Stepper("行数: \(store.settings.rows)", value: bindingRows, in: 3...8)
            Toggle("アイコン名を表示", isOn: bindingLabels)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定の移行 / リセット").font(.headline)
            HStack(spacing: 12) {
                Button { store.exportConfig() } label: {
                    Label("エクスポート…", systemImage: "square.and.arrow.up")
                }
                Button { store.importConfig() } label: {
                    Label("インポート…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button(role: .destructive) { store.resetLayout() } label: {
                    Label("リセット", systemImage: "arrow.counterclockwise")
                }
            }
            Text("エクスポートしたファイルを別の Mac でインポートすると、並び順・フォルダ・外観を復元できます（同じ場所にあるアプリのみ対象）。")
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Bindings

    private var bindingKind: Binding<BackgroundKind> {
        Binding(get: { store.settings.backgroundKind },
                set: { v in store.updateSettings { $0.backgroundKind = v } })
    }
    private var bindingDim: Binding<Double> {
        Binding(get: { store.settings.dim },
                set: { v in store.updateSettings { $0.dim = v } })
    }
    private var bindingColumns: Binding<Int> {
        Binding(get: { store.settings.columns },
                set: { v in store.updateSettings { $0.columns = v } })
    }
    private var bindingRows: Binding<Int> {
        Binding(get: { store.settings.rows },
                set: { v in store.updateSettings { $0.rows = v } })
    }
    private var bindingLabels: Binding<Bool> {
        Binding(get: { store.settings.showLabels },
                set: { v in store.updateSettings { $0.showLabels = v } })
    }
    private var bindingSolidColor: Binding<Color> {
        Binding(get: { Color(hex: store.settings.solidColorHex) },
                set: { v in store.updateSettings { $0.solidColorHex = v.toHex() } })
    }
}
