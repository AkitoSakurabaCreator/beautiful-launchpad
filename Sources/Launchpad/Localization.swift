import Foundation

/// User-facing language preference. `.system` follows the OS preferred language.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, ja, en
    var id: String { rawValue }
}

/// A concrete, resolved rendering language.
enum Lang { case ja, en }

/// Tiny in-code localization table.
///
/// Chosen over `.lproj` / `Localizable.strings` so the language can switch **live**
/// (no relaunch) and so this SwiftPM executable needs no resource-bundle wiring.
/// To add a language: extend `Lang`, add a column to each tuple, and update `resolve`.
enum L {
    enum Key {
        case search, customize, customizeHelp
        case background, bgDesktopBlur, bgTheme, bgImage, bgSolid
        case chooseImage, desktopBlurNote, dim, color
        case layout, columns, rows, showLabels
        case transferReset, export, importConfig, reset, transferNote
        case language, languageSystem, folderDefaultName
        case update, updateCheckNow, updateAuto, updateAvailable, currentVersion
        case addItem, editItem, deleteItem, itemName, itemKind
        case kindApp, kindScript, kindURL, itemTarget, chooseFile
        case chooseIcon, clearIcon, save, cancel, revealInFinder
        case folderColor, defaultColor, scriptHint, urlHint, appHint
        case exportPanelTitle, importPanelTitle, wallpaperPanelTitle
        case back
        case hide, show, hiddenItems, hiddenItemsNote, restoreAll
    }

    /// Resolve the concrete language from the user's choice and the OS locale.
    /// `.system` maps a Japanese OS to `.ja`; everything else falls back to `.en`.
    static func resolve(_ choice: AppLanguage) -> Lang {
        switch choice {
        case .ja: return .ja
        case .en: return .en
        case .system:
            let pref = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return pref.hasPrefix("ja") ? .ja : .en
        }
    }

    static func t(_ key: Key, _ choice: AppLanguage) -> String {
        let pair = table[key] ?? ("", "")
        return resolve(choice) == .ja ? pair.ja : pair.en
    }

    private static let table: [Key: (ja: String, en: String)] = [
        .search:              ("検索", "Search"),
        .customize:           ("カスタマイズ", "Customize"),
        .customizeHelp:       ("カスタマイズ (⌘,)", "Customize (⌘,)"),
        .background:          ("背景", "Background"),
        .bgDesktopBlur:       ("デスクトップぼかし", "Desktop blur"),
        .bgTheme:             ("テーマ", "Theme"),
        .bgImage:             ("画像", "Image"),
        .bgSolid:             ("単色", "Solid"),
        .chooseImage:         ("画像を選択…", "Choose image…"),
        .desktopBlurNote:     ("デスクトップを背景にぼかして表示します。",
                               "Blurs your desktop as the background."),
        .dim:                 ("暗さ", "Dim"),
        .color:               ("色", "Color"),
        .layout:              ("レイアウト", "Layout"),
        .columns:             ("列数", "Columns"),
        .rows:                ("行数", "Rows"),
        .showLabels:          ("アイコン名を表示", "Show icon labels"),
        .transferReset:       ("設定の移行 / リセット", "Transfer / Reset"),
        .export:              ("エクスポート…", "Export…"),
        .importConfig:        ("インポート…", "Import…"),
        .reset:               ("リセット", "Reset"),
        .transferNote:        ("エクスポートしたファイルを別の Mac でインポートすると、並び順・フォルダ・外観を復元できます（同じ場所にあるアプリのみ対象）。",
                               "Import an exported file on another Mac to restore your layout, folders, and appearance (only apps at the same path are matched)."),
        .language:            ("言語", "Language"),
        .languageSystem:      ("システム", "System"),
        .folderDefaultName:   ("フォルダ", "Folder"),
        .update:              ("アップデート", "Update"),
        .updateCheckNow:      ("アップデートを確認…", "Check for Updates…"),
        .updateAuto:          ("起動時に自動で確認", "Check automatically at launch"),
        .updateAvailable:     ("新しいバージョンがあります", "A new version is available"),
        .currentVersion:      ("現在のバージョン", "Current version"),
        .addItem:             ("項目を追加…", "Add Item…"),
        .editItem:            ("項目を編集", "Edit Item"),
        .deleteItem:          ("削除", "Delete"),
        .itemName:            ("名前", "Name"),
        .itemKind:            ("種類", "Type"),
        .kindApp:             ("アプリ", "App"),
        .kindScript:          ("スクリプト / コマンド", "Script / Command"),
        .kindURL:             ("URL", "URL"),
        .itemTarget:          ("対象", "Target"),
        .chooseFile:          ("ファイルを選択…", "Choose File…"),
        .chooseIcon:          ("アイコンを選択…", "Choose Icon…"),
        .clearIcon:           ("アイコンをクリア", "Clear icon"),
        .save:                ("保存", "Save"),
        .cancel:              ("キャンセル", "Cancel"),
        .revealInFinder:      ("Finder で表示", "Reveal in Finder"),
        .folderColor:         ("フォルダの色", "Folder color"),
        .defaultColor:        ("デフォルト", "Default"),
        .scriptHint:          ("スクリプトのパス（要実行権限）かシェルコマンドを入力",
                               "A script path (must be executable) or a shell command"),
        .urlHint:             ("https://… を入力", "Enter https://…"),
        .appHint:             (".app やファイルのパスを選択", "Pick an .app or file path"),
        .exportPanelTitle:    ("Launchpad 設定をエクスポート", "Export Launchpad settings"),
        .importPanelTitle:    ("Launchpad 設定をインポート", "Import Launchpad settings"),
        .wallpaperPanelTitle: ("壁紙画像を選択", "Choose wallpaper image"),
        .back:                ("戻る", "Back"),
        .hide:                ("非表示にする", "Hide"),
        .show:                ("表示", "Show"),
        .hiddenItems:         ("非表示の項目", "Hidden Items"),
        .hiddenItemsNote:     ("右クリックメニューで非表示にした項目です。「表示」で元に戻せます。",
                               "Items you hid via the right-click menu. Tap “Show” to restore them."),
        .restoreAll:          ("すべて表示", "Show All"),
    ]
}
