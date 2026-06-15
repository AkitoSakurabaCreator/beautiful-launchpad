import SwiftUI

/// Customization panel: background (desktop blur / theme / image / solid),
/// grid density, dim, labels, language, plus config export/import.
struct SettingsView: View {
    @EnvironmentObject var store: LaunchpadStore
    @EnvironmentObject var updater: UpdaterController

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

                languageSection

                Divider().overlay(Color.white.opacity(0.2))

                updateSection

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
            Text(store.t(.customize)).font(.system(size: 22, weight: .bold))
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
            Text(store.t(.background)).font(.headline)
            Picker(store.t(.background), selection: bindingKind) {
                Text(store.t(.bgDesktopBlur)).tag(BackgroundKind.desktopBlur)
                Text(store.t(.bgTheme)).tag(BackgroundKind.theme)
                Text(store.t(.bgImage)).tag(BackgroundKind.image)
                Text(store.t(.bgSolid)).tag(BackgroundKind.solid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch store.settings.backgroundKind {
            case .theme:
                themeSwatches
            case .image:
                HStack(spacing: 12) {
                    Button(store.t(.chooseImage)) { store.chooseWallpaper() }
                    if let p = store.settings.wallpaperPath {
                        Text((p as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            case .solid:
                ColorPicker(store.t(.color), selection: bindingSolidColor, supportsOpacity: false)
                    .frame(maxWidth: 160)
            case .desktopBlur:
                Text(store.t(.desktopBlurNote))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack {
                Text(store.t(.dim)).frame(width: 56, alignment: .leading)
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
            Text(store.t(.layout)).font(.headline)
            Stepper("\(store.t(.columns)): \(store.settings.columns)", value: bindingColumns, in: 4...10)
            Stepper("\(store.t(.rows)): \(store.settings.rows)", value: bindingRows, in: 3...8)
            Toggle(store.t(.showLabels), isOn: bindingLabels)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.language)).font(.headline)
            Picker(store.t(.language), selection: bindingLanguage) {
                Text(store.t(.languageSystem)).tag(AppLanguage.system)
                Text("日本語").tag(AppLanguage.ja)
                Text("English").tag(AppLanguage.en)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.update)).font(.headline)
            HStack(spacing: 12) {
                Button { updater.checkForUpdates() } label: {
                    Label(store.t(.updateCheckNow), systemImage: "arrow.down.circle")
                }
                .disabled(!updater.canCheckForUpdates)

                if updater.updateAvailable {
                    Label(store.t(.updateAvailable), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Text("\(store.t(.currentVersion)): \(updater.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Toggle(store.t(.updateAuto), isOn: bindingAutoUpdate)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.transferReset)).font(.headline)
            HStack(spacing: 12) {
                Button { store.exportConfig() } label: {
                    Label(store.t(.export), systemImage: "square.and.arrow.up")
                }
                Button { store.importConfig() } label: {
                    Label(store.t(.importConfig), systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button(role: .destructive) { store.resetLayout() } label: {
                    Label(store.t(.reset), systemImage: "arrow.counterclockwise")
                }
            }
            Text(store.t(.transferNote))
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
    private var bindingLanguage: Binding<AppLanguage> {
        Binding(get: { store.settings.language },
                set: { v in store.updateSettings { $0.language = v } })
    }
    private var bindingAutoUpdate: Binding<Bool> {
        Binding(get: { updater.automaticallyChecksForUpdates },
                set: { v in updater.automaticallyChecksForUpdates = v })
    }
}
