import SwiftUI

/// Customization panel: background (desktop blur / theme / image / solid),
/// grid density, dim, labels, language, plus config export/import.
struct SettingsView: View {
    @EnvironmentObject var store: LaunchpadStore
    @EnvironmentObject var updater: UpdaterController
    @State private var newPresetName = ""
    private var isGlass: Bool { store.settings.layoutStyle == .glass }
    private var glassTransparency: Double { store.settings.glassTransparency }

    var body: some View {
        ZStack {
            Color.black.opacity(isGlass ? 0.30 : 0.5)
                .opacity(isGlass ? GlassPalette.adjustedOpacity(1, transparency: glassTransparency, reduction: 0.55) : 1)
                .ignoresSafeArea()
                .onTapGesture { store.showSettings = false }

            // GeometryReader keeps the card flexible (never inflates the root layout —
            // an over-tall fixed card used to stretch the background image). The header
            // stays pinned while the sections scroll within a height-capped card.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 12)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 18) {
                            backgroundSection
                            sectionDivider
                            gridSection
                            sectionDivider
                            layoutSection
                            sectionDivider
                            animationSection
                            sectionDivider
                            languageSection
                            sectionDivider
                            soundSection
                            sectionDivider
                            updateSection
                            if !store.hiddenItems().isEmpty {
                                sectionDivider
                                hiddenSection
                            }
                            sectionDivider
                            presetsSection
                            sectionDivider
                            transferSection
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 26)
                    }
                }
                .frame(width: 560)
                .frame(maxHeight: max(320, proxy.size.height - 96))
                .background(settingsPanelBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .foregroundColor(.white)
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    private var sectionDivider: some View {
        Divider().overlay(Color.white.opacity(0.2))
    }

    private var settingsPanelBackground: some View {
        RoundedRectangle(cornerRadius: isGlass ? 30 : 24, style: .continuous)
            .fill(isGlass ? Color.clear : Color.white.opacity(0.001))
            .background {
                if isGlass {
                    LiquidGlassBackground(
                        shape: RoundedRectangle(cornerRadius: 30, style: .continuous),
                        tint: GlassPalette.coolEdge,
                        transparency: glassTransparency,
                        reduceLiveBlur: store.settings.usesVideoBackground,
                        strokeOpacity: 0.40,
                        shadowOpacity: 0.24
                    )
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: isGlass ? 30 : 24, style: .continuous)
                    .stroke(
                        Color.white.opacity(isGlass
                            ? GlassPalette.adjustedOpacity(0.30, transparency: glassTransparency, reduction: 0.35)
                            : 0.15),
                        lineWidth: 1
                    )
            )
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
                Text(store.t(.bgSlideshow)).tag(BackgroundKind.slideshow)
                Text(store.t(.bgVideo)).tag(BackgroundKind.video)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch store.settings.backgroundKind {
            case .theme:
                themeSwatches
            case .image:
                pickedFileRow(title: store.t(.chooseImage), path: store.settings.wallpaperPath) {
                    store.chooseWallpaper()
                }
            case .solid:
                ColorPicker(store.t(.color), selection: bindingSolidColor, supportsOpacity: false)
                    .frame(maxWidth: 160)
            case .desktopBlur:
                Text(store.t(.desktopBlurNote))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                HStack {
                    Text(store.t(.blurStrength)).frame(width: 96, alignment: .leading)
                    Slider(value: bindingBlurIntensity, in: 0...1)
                    Text("\(Int(store.settings.blurIntensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36)
                }
            case .slideshow:
                pickedFileRow(title: store.t(.chooseFolder), path: store.settings.slideshowFolder) {
                    store.chooseSlideshowFolder()
                }
                Toggle(store.t(.slideshowRandom), isOn: bindingSlideshowRandom)
                HStack {
                    Text(store.t(.slideshowInterval)).frame(width: 96, alignment: .leading)
                    Slider(value: bindingSlideshowInterval, in: 3...300, step: 1)
                    Text("\(Int(store.settings.slideshowInterval))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 32)
                }
            case .video:
                pickedFileRow(title: store.t(.chooseVideo), path: store.settings.videoPath) {
                    store.chooseVideo()
                }
                pickedFileRow(title: store.t(.chooseFolder), path: store.settings.videoFolder) {
                    store.chooseVideoFolder()
                }
                if store.settings.videoFolder != nil {
                    Toggle(store.t(.slideshowRandom), isOn: bindingVideoRandom)
                }
                Toggle(store.t(.videoSound), isOn: bindingVideoSound)
                if !store.settings.videoMuted {
                    HStack {
                        Text(store.t(.volume)).frame(width: 96, alignment: .leading)
                        Slider(value: bindingVideoVolume, in: 0...1)
                        Text("\(Int(store.settings.videoVolume * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36)
                    }
                }
            }

            HStack {
                Text(store.t(.dim)).frame(width: 56, alignment: .leading)
                Slider(value: bindingDim, in: 0...0.6)
            }
        }
    }

    /// A "choose…" button plus the basename of the currently selected file/folder.
    private func pickedFileRow(title: String, path: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(title, action: action)
            if let p = path {
                Text((p as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.animation)).font(.headline)
            Toggle(store.t(.animationsEnabled), isOn: bindingAnimationsEnabled)
            if store.settings.animationsEnabled {
                Picker(store.t(.openAnimation), selection: bindingOpenAnimation) {
                    Text(store.t(.animZoom)).tag(OpenAnimation.zoom)
                    Text(store.t(.animFade)).tag(OpenAnimation.fade)
                    Text(store.t(.animSlide)).tag(OpenAnimation.slide)
                    Text(store.t(.animNone)).tag(OpenAnimation.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack {
                    Text(store.t(.animationSpeed)).frame(width: 96, alignment: .leading)
                    Slider(value: bindingAnimationSpeed, in: 0.5...2.0, step: 0.25)
                    Text(String(format: "%.2g×", store.settings.animationSpeed))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36)
                }
            }
            Toggle(store.t(.freePlacement), isOn: bindingFreePlacement)
            if store.settings.freePlacement {
                Text(store.t(.freePlacementNote))
                    .font(.caption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.t(.realign)) { store.realignToGrid() }
                    .font(.caption)
            }
        }
    }

    private var themeSwatches: some View {
        // Wrapping grid so any number of theme presets stays inside the card width
        // (an HStack overflowed once the preset count grew).
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 90), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            ForEach(Theming.themes) { theme in
                let selected = store.settings.themeIndex == theme.id
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: theme.colors,
                                         startPoint: theme.start, endPoint: theme.end))
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(selected ? 0.95 : 0.2),
                                    lineWidth: selected ? 3 : 1)
                    )
                    .contentShape(Rectangle())
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
            Stepper("\(store.t(.folderColumns)): \(store.settings.folderColumns)", value: bindingFolderColumns, in: 3...8)
            Stepper("\(store.t(.folderRows)): \(store.settings.folderRows)", value: bindingFolderRows, in: 2...6)
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.sound)).font(.headline)
            Toggle(store.t(.launchSound), isOn: bindingLaunchSound)
            if store.settings.launchSound {
                Picker(store.t(.launchSoundName), selection: bindingLaunchSoundName) {
                    ForEach(LaunchpadStore.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: 240)
                .disabled(store.settings.launchSoundPath != nil)

                HStack(spacing: 10) {
                    Button(store.t(.chooseSound)) { store.chooseLaunchSound() }
                    if let p = store.settings.launchSoundPath {
                        Text((p as NSString).lastPathComponent)
                            .font(.caption).foregroundColor(.white.opacity(0.6))
                            .lineLimit(1).truncationMode(.middle)
                        Button(store.t(.clearSound)) { store.clearLaunchSound() }
                            .buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.layoutStyle)).font(.headline)
            Picker(store.t(.layoutStyle), selection: bindingLayoutStyle) {
                Text(store.t(.layoutClassic)).tag(LayoutStyle.classic)
                Text(store.t(.layoutGlass)).tag(LayoutStyle.glass)
                Text(store.t(.layoutAndroid)).tag(LayoutStyle.android)
                Text(store.t(.layoutWindows)).tag(LayoutStyle.windows)
                Text(store.t(.layoutCyber)).tag(LayoutStyle.cyber)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.settings.layoutStyle == .glass {
                HStack {
                    Text(store.t(.glassTransparency)).frame(width: 96, alignment: .leading)
                    Slider(value: bindingGlassTransparency, in: 0...1)
                    Text("\(Int(store.settings.glassTransparency * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36)
                }
            }
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

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t(.presets)).font(.headline)

            // Save the current configuration as a new named preset.
            HStack(spacing: 8) {
                TextField(store.t(.presetName), text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button(store.t(.savePreset)) {
                    if store.saveCurrentAsPreset(name: newPresetName) { newPresetName = "" }
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !store.presets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.presets) { preset in
                        HStack(spacing: 8) {
                            TextField("", text: Binding(
                                get: { preset.name },
                                set: { store.renamePreset(preset.id, $0) }
                            ))
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                            Spacer()
                            Button(store.t(.apply)) { store.applyPreset(preset.id) }
                            Button(store.t(.presetUpdate)) { store.updatePreset(preset.id) }
                                .font(.caption)
                            Button(role: .destructive) { store.deletePreset(preset.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            }

            Text(store.t(.presetsNote))
                .font(.caption).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
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

    private var hiddenSection: some View {
        let items = store.hiddenItems()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.t(.hiddenItems)).font(.headline)
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Button(store.t(.restoreAll)) {
                    for item in items { store.unhide(item.id) }
                }
                .font(.caption)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(nsImage: store.icon(for: item))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 26, height: 26)
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(store.t(.show)) { store.unhide(item.id) }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            }
            .frame(maxHeight: 168)

            Text(store.t(.hiddenItemsNote))
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
    private var bindingBlurIntensity: Binding<Double> {
        Binding(get: { store.settings.blurIntensity },
                set: { v in store.updateSettings { $0.blurIntensity = v } })
    }
    private var bindingVideoSound: Binding<Bool> {
        Binding(get: { !store.settings.videoMuted },
                set: { v in store.updateSettings { $0.videoMuted = !v } })
    }
    private var bindingVideoVolume: Binding<Double> {
        Binding(get: { store.settings.videoVolume },
                set: { v in store.updateSettings { $0.videoVolume = v } })
    }
    private var bindingVideoRandom: Binding<Bool> {
        Binding(get: { store.settings.videoRandom },
                set: { v in store.updateSettings { $0.videoRandom = v } })
    }
    private var bindingFolderColumns: Binding<Int> {
        Binding(get: { store.settings.folderColumns },
                set: { v in store.updateSettings { $0.folderColumns = v } })
    }
    private var bindingFolderRows: Binding<Int> {
        Binding(get: { store.settings.folderRows },
                set: { v in store.updateSettings { $0.folderRows = v } })
    }
    private var bindingLaunchSound: Binding<Bool> {
        Binding(get: { store.settings.launchSound },
                set: { v in store.updateSettings { $0.launchSound = v } })
    }
    private var bindingLaunchSoundName: Binding<String> {
        Binding(get: { store.settings.launchSoundName },
                set: { v in store.updateSettings { $0.launchSoundName = v } })
    }
    private var bindingSlideshowRandom: Binding<Bool> {
        Binding(get: { store.settings.slideshowRandom },
                set: { v in store.updateSettings { $0.slideshowRandom = v } })
    }
    private var bindingSlideshowInterval: Binding<Double> {
        Binding(get: { store.settings.slideshowInterval },
                set: { v in store.updateSettings { $0.slideshowInterval = v } })
    }
    private var bindingAnimationsEnabled: Binding<Bool> {
        Binding(get: { store.settings.animationsEnabled },
                set: { v in store.updateSettings { $0.animationsEnabled = v } })
    }
    private var bindingAnimationSpeed: Binding<Double> {
        Binding(get: { store.settings.animationSpeed },
                set: { v in store.updateSettings { $0.animationSpeed = v } })
    }
    private var bindingOpenAnimation: Binding<OpenAnimation> {
        Binding(get: { store.settings.openAnimation },
                set: { v in store.updateSettings { $0.openAnimation = v } })
    }
    private var bindingFreePlacement: Binding<Bool> {
        Binding(get: { store.settings.freePlacement },
                set: { v in store.updateSettings { $0.freePlacement = v } })
    }
    private var bindingLayoutStyle: Binding<LayoutStyle> {
        Binding(get: { store.settings.layoutStyle },
                set: { v in store.updateSettings { $0.layoutStyle = v } })
    }
    private var bindingGlassTransparency: Binding<Double> {
        Binding(get: { store.settings.glassTransparency },
                set: { v in store.updateSettings { $0.glassTransparency = v } })
    }
    private var bindingAutoUpdate: Binding<Bool> {
        Binding(get: { updater.automaticallyChecksForUpdates },
                set: { v in updater.automaticallyChecksForUpdates = v })
    }
}
