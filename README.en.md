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
- ✋ **Drag to reorder** — drop near the **edge** of an icon to reorder; page flips at the page edge
- 💾 **Persistent layout** — saves order and folders to `~/Library/Application Support/Launchpad/layout.json`
- 🚀 **Click to actually launch** → Launchpad closes automatically after launching
- 🎞 **Open/close animation** — smooth fade + zoom on open and close (no abrupt disappearance when closing)
- 🖥 **Multi-monitor support** — opens on **the screen where the cursor is** at launch time
- 🎨 **Appearance customization** — background (desktop blur / theme / image / solid color), columns & rows, dimming, icon-label toggle
- 📦 **Export / import settings** — write order, folders, and appearance to JSON and **load them on another Mac**
- ⌨️ **Esc** to (close settings/folder → clear search →) quit; click empty space to quit

---

## Download (prebuilt app)

The latest prebuilt `Beautiful Launchpad.app` is available from [Releases](../../releases)
(GitHub Actions builds and attaches it automatically on `v*` tag push).

1. Download `BeautifulLaunchpad.zip` from Releases and unzip it
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
| Drag an app **outside the panel** from inside a folder | Remove it from the folder back to the home screen (the "−" button also works) |
| Drag an app **onto another app** inside a folder | Reorder within the folder |
| ⚙️ button (top-right) / **⌘,** | Open the customization screen |
| Esc | Close settings/folder → clear search → quit |
| Click empty space | Quit |

To reset the layout, use "Reset" on the customization screen, or delete
`~/Library/Application Support/Launchpad/layout.json`.

---

## Customization / migrating settings

Open the customization screen with the ⚙️ button (top-right) or **⌘,**.

- **Background**: desktop blur (classic) / theme (6 gradients) / image (pick any wallpaper) / solid color
- **Dimming**: opacity of the dark overlay on top of the background
- **Layout**: columns (4–10) and rows (3–8)
- **Icon labels**: toggle labels ON/OFF

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
    ├── Models.swift              # AppInfo / Folder / persistence models
    ├── AppScanner.swift          # installed-app scanning + icon retrieval
    ├── LaunchpadStore.swift      # state management / paging / search / D&D / folders / persistence
    ├── LaunchpadView.swift       # root / pager / grid / search / dots
    ├── IconViews.swift           # app/folder tile rendering
    ├── FolderViews.swift         # folder overlay
    └── DragDrop.swift            # DropDelegate (center = folder / edge = reorder detection)
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
