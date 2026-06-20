# Beautiful Launchpad (a beautiful, native macOS launcher)

**English** | [日本語](README.md)

This is more than just a revival of the classic **Launchpad** that was removed in macOS 26 (Tahoe).
It's a **beautiful** native macOS launcher that can look like the **familiar classic**, or wear a
**custom design with your own background, theme, and layout**. It lays out your installed apps in a
full-screen grid, supports search, paging, folders, and drag-to-reorder, and **actually launches apps**
on click.

- Language/Tech: **Swift 5.9+ / SwiftUI + AppKit** (SwiftPM — no full Xcode required, builds with Command Line Tools only)
- Verified on: macOS 26.5.1 / Apple Silicon (arm64)

---

## Features (classic recreation + free customization)

- 🖥 **Full-screen frosted-glass background** (blurs the desktop via `NSVisualEffectView` behind-window blur)
- 🔍 **Instant search** — just start typing right after launch to filter across all apps
- 🗂 **Automatic app discovery** — scans `/Applications`, `/System/Applications`, `~/Applications`, etc.
  and lists them with icons (also picks up bundled apps in subfolders, one level deep)
- 📄 **Multiple pages + page dots** — move by scroll / ←→ keys / clicking a dot
- 📁 **Folders** — create by dragging an app onto the **center** of another app, add by dragging into a folder,
  open as an overlay to launch, rename, or remove
- 📂 **Nested folders (sub-folders)** — inside an open folder, drag an item onto the **center** of another item
  to create / enter a sub-folder; tap to drill in and use the **‹ back** button to go up one level
- 📑 **Paginated folders** — folder contents automatically split across multiple pages as they grow
  (page dots + drag to the left/right edge to flip); the card stays a fixed size regardless of item count
- ✋ **Drag to reorder** — drop near the **edge** of an icon to reorder; page flips at the page edge
- 💾 **Persistent layout** — saves order and folders to `~/Library/Application Support/Launchpad/layout.json`
- 🚀 **Click to actually launch** → Launchpad closes automatically after launching
- 🎞 **Open/close animation (customizable)** — pick the transition from **zoom / fade / slide / none**, adjust the speed (0.5–2.0×), and toggle animations on/off entirely
- 🖥 **Multi-monitor support** — opens on **the screen where the cursor is** at launch time
- 🎨 **Appearance customization** — background (desktop blur / theme / image / **slideshow** / **video** / solid color), blur strength, columns & rows, folder columns & rows, dimming, icon-label toggle
- 🖼 **Slideshow background** — cross-fade through the images in a folder, sequentially or shuffled (interval 3–300s)
- 🎬 **Video background** — loop a single video seamlessly, or play a folder of videos as a playlist (sequential or shuffled); mute toggle and volume control included
- 🧱 **Layout style** — switch the icon & folder look between Classic / Android / Windows / **Cyber** (neon glow)
- 📌 **Free icon placement** — place icons anywhere instead of on the grid (use "Re-align" to snap back anytime)
- 🌄 **Per-page background** — right-click a page's empty space to give that page its own image or preset color
- 📟 **Widgets** — place **clock / date / notes / battery / system info / weather / image / video** widgets on a page; drag to move, drag the corner to resize, and use "Hide window" to drop the card chrome and blend into the background (weather uses Open-Meteo — no API key, auto-located by IP)
- 🔊 **App launch sound** — play one of 8 system sounds (Pop / Tink / Glass / Hero / Submarine / Ping / Funk / Morse) or a custom sound file when launching
- 👋 **First-run onboarding** — a welcome screen on first launch that guides you to Privacy settings so images from protected folders (Desktop/Documents) can be used as backgrounds
- 🧩 **User-defined items** — manually add **apps / scripts & shell commands / URLs / random image (folder)** (with an optional custom icon). Add them by right-clicking the background or an icon → "Add Item"
- 🖱 **Right-click menu** — edit/delete your custom items, **reveal an app in Finder**, **hide an item**, or add one on the spot
- 🙈 **Hide / show items** — right-click → "**Hide**" to take an app or custom item out of the grid and search
  (it won't reappear after a rescan); restore it anytime from the **"Hidden Items"** section in Settings via "Show" / "Show All"
- 🏷 **Color-coded folders** — give a folder a preset tint (9 colors + default)
- 🌐 **Multilingual** — Japanese / English / follow-system, switchable **live with no relaunch**
- ⬆️ **Auto-update** — checks automatically at launch (Sparkle); manual check available from the settings panel
- 📦 **Export / import settings** — write order, folders, and appearance to JSON and **load them on another Mac**
- ⌨️ **Esc** to (close settings/folder → clear search →) quit; click empty space to quit

---

## Download (prebuilt app)

The latest prebuilt `Beautiful Launchpad.app` is available from [Releases](../../releases)
(GitHub Actions builds and attaches it automatically on `v*` tag push).

1. Download the latest release `.zip` from Releases and unzip it (the asset name may vary by release)
2. Move `Beautiful Launchpad.app` to `/Applications` or similar
3. **First launch only**: because local builds are **ad-hoc signed** and not notarized, the downloaded
   version is blocked by Gatekeeper. Open it with one of the following:
   - **Right-click → "Open"** on `Beautiful Launchpad.app` → choose "Open" (first time only)
   - Or remove the quarantine attribute in Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Beautiful Launchpad.app"
     ```

> An `.app` you build yourself (below) isn't downloaded from the internet, so this step isn't needed.
> No App Store distribution or Apple notarization is done (this is intended for personal use).

---

## Building

```bash
# in this directory
./build-app.sh            # release build → generates Beautiful Launchpad.app and ad-hoc signs it
# or for development
./build-app.sh debug
```

Output: `./Beautiful Launchpad.app`

### Launch

```bash
open "./Beautiful Launchpad.app"
# or double-click in Finder
```

> On first launch, Gatekeeper may say "cannot verify the developer." In that case, use
> **Right-click → "Open"**, or allow it from "System Settings → Privacy & Security"
> (because it's a local ad-hoc-signed build).

### Quick run during development (no bundle)

```bash
swift run          # run in debug
swift build        # compile only
```

---

## Controls

| Action | Behavior |
|---|---|
| Click an app icon | Launch that app and close Launchpad |
| Type | Search (the search field is focused automatically right after launch) |
| ← / → keys, horizontal scroll, dots | Change page |
| Drag an icon (to an edge) | Reorder. Flips the page at the screen edge |
| Drag an icon onto the center of another icon | Create a folder / add to a folder |
| Click a folder | Open the folder (rename available) |
| Drag an item **onto the center of another item** inside a folder | Create a sub-folder / move it into one (nesting) |
| Drag an item **elsewhere** inside a folder | Reorder within the folder |
| Drag an item **to the left/right edge** inside a folder | Flip the folder page |
| Drag an item **outside the card (dark backdrop)** from inside a folder | Move it out, up one level (the "−" button also works) |
| Tap a sub-folder / **‹ back** | Drill into it / go up one level |
| **Right-click** an icon / folder / the background | Context menu (add an item, **add a widget**, edit/delete, reveal in Finder, **hide an item**, set **this page's background**, etc.) |
| Drag a widget's **title bar or body** / its bottom-right corner handle | Move / resize the widget (Notes is moved by its title bar — its body is for editing) |
| **Right-click** a widget | Choose media (image/video), toggle mute (video), **show/hide window**, **lock/unlock**, delete |
| Hover over a widget | Shows sliders at the bottom: **rotation** (all), **opacity** (image/video), **volume/mute** (video) |
| ⚙️ button (top-right) / **⌘,** | Open the customization screen |
| Esc | Close settings/folder → clear search → quit |
| Click empty space | Quit |

To reset the layout, use "Reset" on the customization screen, or delete
`~/Library/Application Support/Launchpad/layout.json`.

---

## Customization / migrating settings

Open the customization screen with the ⚙️ button (top-right) or **⌘,**.

- **Background**: desktop blur (classic) / theme (8 presets: Midnight, Aurora, Sunset, Forest, Graphite, Rose, Cyber, Glass) / image (any wallpaper) / slideshow (an image folder) / video (a single file or a folder playlist) / solid color
  - **Desktop blur**: adjust 0–100% with the "Blur strength" slider
  - **Slideshow**: pick a folder, then set shuffle on/off and the interval (3–300s); images cross-fade
  - **Video**: pick a single video or a folder (shuffle available for a folder). Turn on "Play video audio" to hear sound and adjust the volume
- **Dimming**: opacity of the dark overlay on top of the background
- **Layout**: columns (4–10) and rows (3–8), plus folder columns (3–8) and rows (2–6)
- **Layout style**: Classic / Android / Windows / Cyber (neon glow)
- **Icon labels**: toggle labels ON/OFF
- **Animation**: enable/disable, open/close effect (zoom / fade / slide / none), and speed (0.5–2.0×)
- **Free icon placement**: turn on to place icons anywhere; turn off to auto-align like before ("Re-align" snaps everything back)
- **Sound**: toggle the app launch sound, choose a system sound (8 options), or set a custom sound file
- **Language**: Japanese / English / follow-system (switches without relaunch)
- **Update**: toggle automatic check at launch, plus a manual "Check for Updates…"

### Adding items / folder colors

- **Add an item**: **right-click the background or an icon → "Add Item…"** to register an app, a script/shell command, a URL, or a **random image (folder)** (a custom icon can be set too). Scripts & commands run through a shell (must be executable). "Random image (folder)" opens a random picture from the chosen folder each time you click it.
- **Folder color**: pick a tint from the color swatches in the open-folder view. The leading "−" swatch resets it to the default (no tint).

### Per-page background

- **Right-click a page's empty space → "This page's background"** to give that single page its own image or preset color. Use "Clear background" to revert to the shared background.

### Widgets

- **Add**: **right-click a page's empty space → "Add Widget"** to place a clock, date, notes, battery, system, weather, image, or video widget.
- **Move / resize**: drag the title bar (the handle at the top) or the **widget body** to move; drag the bottom-right corner handle to resize (Notes is moved via its title bar, since its body is for editing). Position and size are stored normalized, so they survive window/display size changes.
- **Hover controls (sliders)**: hover over a widget to reveal sliders at the bottom for **rotation** (all widgets, −180…180°), **opacity** (image/video), and **volume & mute** (video).
- **Right-click a widget**: re-pick the media for image/video widgets, toggle mute for video, **"Hide/Show window"** to drop the card background/border (so transparent PNGs and overlay videos blend in), or **"Lock/Unlock"** to prevent accidental changes (a locked widget can't be moved, resized, or hovered). Delete is here too.
- **Weather**: uses Open-Meteo (no API key) and auto-locates by IP (no Location permission), refreshing every 15 minutes. Shows "—" when offline.
- **Notes**: editable in place; the text is saved in `layout.json`.
- Widgets are hidden while searching, and their layout is persisted in `layout.json`.

### Hiding / restoring items

- **Hide**: **right-click an app or custom item → "Hide"** to take it out of the grid, folders, and search. Hidden items are not re-added on a rescan (folders themselves can't be hidden).
- **Restore**: a **"Hidden Items"** section appears in the customization screen only when something is hidden. Bring items back with **"Show"** per item, or **"Show All"** at once.
- The hidden selection is saved in `layout.json`, so it persists across app restarts.

### Migrating to another Mac (export / import)

- Use **"Export…"** on the customization screen to write `launchpad-config.json` (order, folders, appearance).
- On another Mac, load it via **"Import…"** to restore.

> Notes:
> - The layout references apps by **file path**. Standard apps in `/Applications` and `/System/Applications`
>   are in the same location on any Mac and migrate fine, but **apps that don't exist on the destination are skipped**.
> - **Wallpaper images are referenced by file path**, so the image itself isn't copied to the destination
>   (place the image in the same location, or pick it again on the destination).
> - Appearance settings (theme, dimming, columns, etc.) migrate completely.

Settings file location:
`~/Library/Application Support/Launchpad/` (`layout.json` and `settings.json`)

---

## Structure

```
LaunchPad/
├── Package.swift                 # SwiftPM (executable target, macOS 13+)
├── Info.plist                    # for the .app bundle
├── build-app.sh                  # build + .app packaging + ad-hoc signing
└── Sources/Launchpad/
    ├── LaunchpadApp.swift        # @main / AppDelegate / full-screen window / key & scroll monitoring
    ├── Support.swift             # GridGeometry / VisualEffectView / chunk
    ├── Models.swift              # AppInfo / Folder / CustomItem / WidgetItem / enums / persistence & settings models (order, folders, hidden, free placement, per-page backgrounds, widgets, all AppSettings)
    ├── AppScanner.swift          # installed-app scanning + icon retrieval
    ├── LaunchpadStore.swift      # state / paging / search / D&D / folders (nesting) / hide / free placement / per-page backgrounds / widgets / launch sound / persistence
    ├── LaunchpadView.swift       # root / pager / grid / search / dots / right-click menu
    ├── IconViews.swift           # app/folder tile rendering (folder mini-preview)
    ├── FolderViews.swift         # folder overlay (nesting, pagination, color)
    ├── DragDrop.swift            # DropDelegate (center = folder / edge = reorder & page-flip)
    ├── CustomItems.swift         # add/edit overlay for user items (app / script / URL / random image)
    ├── Animations.swift          # animation policy (speed multiplier, open/close transitions, enable/disable — centralized)
    ├── BackgroundMedia.swift     # video background (single loop / folder playlist) and image slideshow background
    ├── Onboarding.swift          # first-run welcome / permissions dialog
    ├── Widgets.swift             # widgets (clock/date/notes/battery/system/weather/image/video) rendering, placement, resizing
    ├── SettingsView.swift        # customization screen (background, layout, layout style, animation, sound, language, update, hidden items, export/import)
    ├── Theming.swift             # background rendering (blur / 8 themes / image / solid + blur strength) + Cyber color palette
    ├── Localization.swift        # in-code i18n table (Japanese / English / follow-system, live switch)
    └── Updater.swift             # Sparkle auto-update (dismiss guard for the full-screen overlay)
```

---

## Known limitations / roadmap

- **App icon (for Dock display)**: place `icon.png` (square, 1024px+ recommended) in the project root and run
  `build-app.sh`; it auto-generates and embeds `AppIcon.icns` via `sips`/`iconutil`
  (if there's no `icon.png`, the existing `AppIcon.icns` is used as-is).
- Drag & drop / folder creation are **verified through logic implementation, compilation, and launch**, but
  manual verification of interactive behavior on a real machine is recommended (full GUI automated testing
  isn't possible in the build environment).
- Multi-monitor supports the "open on the screen with the cursor" approach. Simultaneous full-screen display
  (the old behavior of dimming all monitors) is not supported — can be added if needed.
- Global hotkeys (e.g. invoke with F4) and running as a resident process are not implemented.
  Resident + hotkey or menu-bar residence can be added if needed.
- With full Xcode, an `.xcodeproj`, App Sandbox, and notarization are also possible.

---

## Contributing

Improvement ideas and bug reports are welcome via Issues / Pull Requests. Feel free to reach out.

## License

[MIT License](LICENSE) © 2026 AkitoSakurabaCreator

Anyone is free to use, modify, and redistribute it (keeping the copyright notice is the only condition).
