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
        case blurStrength, folderColumns, folderRows, sound, launchSound, launchSoundName
        case bgSlideshow, bgVideo, chooseFolder, chooseVideo, slideshowInterval, slideshowRandom
        case animation, animationsEnabled, animationSpeed, openAnimation
        case animZoom, animFade, animSlide, animNone
        case pageBackground, pageBgImage, pageBgClear
        case layoutStyle, layoutClassic, layoutAndroid, layoutWindows, layoutCyber
        case freePlacement, freePlacementNote, realign, kindRandomImage, randomImageHint
        case onboardingTitle, onboardingBody, openPrivacy, continueButton
        case chooseSound, clearSound, customSound, videoSound, newPage, volume
        case addWidget, widgetClock, widgetDate, widgetNotes, widgetBattery, widgetSystem, widgetWeather
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
        .blurStrength:        ("ぼかしの強さ", "Blur strength"),
        .folderColumns:       ("フォルダの列数", "Folder columns"),
        .folderRows:          ("フォルダの行数", "Folder rows"),
        .sound:               ("サウンド", "Sound"),
        .launchSound:         ("アプリ起動音", "App launch sound"),
        .launchSoundName:     ("音", "Sound effect"),
        .bgSlideshow:         ("スライドショー", "Slideshow"),
        .bgVideo:             ("動画", "Video"),
        .chooseFolder:        ("フォルダを選択…", "Choose Folder…"),
        .chooseVideo:         ("動画を選択…", "Choose Video…"),
        .slideshowInterval:   ("切替間隔(秒)", "Interval (s)"),
        .slideshowRandom:     ("ランダム順", "Shuffle"),
        .animation:           ("アニメーション", "Animation"),
        .animationsEnabled:   ("アニメーションを有効化", "Enable animations"),
        .animationSpeed:      ("速度", "Speed"),
        .openAnimation:       ("開閉エフェクト", "Open/close effect"),
        .animZoom:            ("ズーム", "Zoom"),
        .animFade:            ("フェード", "Fade"),
        .animSlide:           ("スライド", "Slide"),
        .animNone:            ("なし", "None"),
        .pageBackground:      ("このページの背景", "This page's background"),
        .pageBgImage:         ("画像を設定…", "Set image…"),
        .pageBgClear:         ("背景をクリア", "Clear background"),
        .layoutStyle:         ("レイアウト", "Layout style"),
        .layoutClassic:       ("クラシック", "Classic"),
        .layoutAndroid:       ("Android風", "Android"),
        .layoutWindows:       ("Windows風", "Windows"),
        .layoutCyber:         ("サイバー", "Cyber"),
        .freePlacement:       ("アイコンを自由配置", "Free icon placement"),
        .freePlacementNote:   ("オンにするとアイコンを好きな位置に置けます。オフで従来の自動整列に戻ります。",
                               "When on, place icons anywhere. Turn off to auto-align like before."),
        .realign:             ("自動整列に戻す", "Re-align"),
        .kindRandomImage:     ("ランダム画像 (フォルダ)", "Random image (folder)"),
        .randomImageHint:     ("クリックするとフォルダ内のランダムな画像を開きます",
                               "Opens a random image from the folder when clicked"),
        .onboardingTitle:     ("ようこそ", "Welcome"),
        .onboardingBody:      ("Beautiful Launchpad はインストール済みアプリを一覧表示します。壁紙やスライドショーに保護されたフォルダ（デスクトップ/書類など）の画像を使う場合は、システム設定 → プライバシーとセキュリティ でアクセスを許可してください。",
                               "Beautiful Launchpad lists your installed apps. To use images from protected folders (Desktop/Documents) for wallpaper or slideshow, grant access in System Settings → Privacy & Security."),
        .openPrivacy:         ("プライバシー設定を開く", "Open Privacy Settings"),
        .continueButton:      ("はじめる", "Get Started"),
        .chooseSound:         ("音を選択…", "Choose Sound…"),
        .clearSound:          ("クリア", "Clear"),
        .customSound:         ("カスタム音を使用中", "Using custom sound"),
        .videoSound:          ("動画の音を出す", "Play video audio"),
        .newPage:             ("新しいページ", "New page"),
        .volume:              ("音量", "Volume"),
        .addWidget:           ("ウィジェットを追加", "Add Widget"),
        .widgetClock:         ("時計", "Clock"),
        .widgetDate:          ("日付", "Date"),
        .widgetNotes:         ("メモ", "Notes"),
        .widgetBattery:       ("バッテリー", "Battery"),
        .widgetSystem:        ("システム", "System"),
        .widgetWeather:       ("天気", "Weather"),
    ]
}
