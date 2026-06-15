# 自動アップデート設定（Sparkle）

Launchpad は [Sparkle](https://sparkle-project.org) で自己アップデートします。**appcast**
フィードを確認し、新しいビルドがあれば **EdDSA 署名済みの更新アーカイブ（zip）**を
検証してからダウンロード・適用します。

以下は **一度きりのセットアップ**です。完了後は `vX.Y.Z` タグを push するたびに、
既存ユーザーへ自動でアップデートが配信されます。

## 仕組み

- `.github/workflows/release.yml` が `.app` をビルド → zip → GitHub Release へ添付 →
  EdDSA 秘密鍵で zip を署名 → `appcast.xml` を `main` に書き出します。
- アプリは `Info.plist` の `SUFeedURL`
  （`https://raw.githubusercontent.com/AkitoSakurabaCreator/beautiful-launchpad/main/appcast.xml`）
  を読みます。
- アップデートは `SUPublicEDKey` で検証されます。**正しい署名でなければ適用しません**（フェイルセーフ）。
- アプリ内：1 日 1 回バックグラウンドで控えめに確認。設定（⌘,）→「アップデート」に
  手動確認ボタンと自動確認トグルがあります。フルスクリーンの刹那的オーバーレイなので、
  更新ダイアログ表示中は自動で閉じないようガードしてあります。

## 一度きりのセットアップ

### 1. 署名鍵を生成

```sh
curl -fsSL -o sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz
mkdir sparkle && tar -xf sparkle.tar.xz -C sparkle
./sparkle/bin/generate_keys     # 秘密鍵を Keychain に保存し、PUBLIC キーを表示
```

Keychain の許可ダイアログが出たら承認してください。次のように出力されます：

```
<key>SUPublicEDKey</key>
<string>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=</string>
```

### 2. 公開鍵を Info.plist に貼る

`Info.plist` の `SUPublicEDKey` の**プレースホルダ値**を、上で表示された文字列に置き換えます。
（同梱値はランダムなプレースホルダです。置き換えるまでアップデートは検証に失敗します。）

### 3. 秘密鍵を GitHub Secret に登録

```sh
./sparkle/bin/generate_keys -x sparkle_private_key.txt   # 秘密鍵をファイルへエクスポート
```

GitHub の **Settings → Secrets and variables → Actions → New repository secret**：

- Name: `SPARKLE_ED_PRIVATE_KEY`
- Value: `sparkle_private_key.txt` の中身

登録後はファイルを削除：`rm sparkle_private_key.txt`（鍵は Keychain と Secret にのみ残す）。

## リリースの切り方

1. `Info.plist` の **両方**を上げる：
   - `CFBundleShortVersionString`（表示用、例 `1.0.1`）
   - `CFBundleVersion`（ビルド番号 — **必ず増やす**、例 `2`）。Sparkle はこれで新旧を比較します。
2. コミットしてタグを push：
   ```sh
   git tag v1.0.1 && git push origin v1.0.1
   ```
3. CI がビルド → Release 公開 → 署名 → `main` の `appcast.xml` を更新。
4. 既存ユーザーは次回の日次チェック（または設定→「アップデートを確認…」）で更新を受け取ります。

> ⚠️ `CFBundleVersion` を増やさないと、Sparkle は新しいビルドと見なしません。

> 🛡 **CI 安全ゲート**: ビルド前の preflight が次を検査し、満たさないと **Release 作成前に失敗**します。
> ① 公開鍵が placeholder でない ② `SPARKLE_ED_PRIVATE_KEY` secret あり ③ タグ == `v{CFBundleShortVersionString}`
> ④ `CFBundleVersion` が公開済み appcast の最新版より大きい。
> 検査を意図的に飛ばす試験リリースは末尾 `-test` のタグ（例 `v1.0.1-test`）を使うと失敗が警告に降格します。

## 注意・制限

- アップデートは **フル更新**（差分なし）。appcast は最新バージョンのエントリを保持します。
- アプリは **ad-hoc 署名**（Developer ID / notarization なし）。EdDSA で更新の完全性は
  担保されますが、ブラウザでダウンロードした初回起動時は Gatekeeper の「開発元未確認」警告が出ます
  （Sparkle 自身がダウンロードした更新は quarantine が付かないため警告は出ません）。
- CI は **arm64 のみ**ビルド（Apple Silicon）。Intel 対応には universal ビルド化が別途必要。
- appcast のホスティング代替：`main` の raw URL の代わりに GitHub Pages で `appcast.xml` を
  配信し、`SUFeedURL` をそれに合わせて変更してもかまいません。
- **署名の範囲**：**更新アーカイブ（zip）は EdDSA 署名**され `SUPublicEDKey` で検証されます。
  一方 **appcast フィード XML 自体は既定では署名しません**（HTTPS＋ホスト整合性に依存）。
  appcast を可変ブランチ（`main` の raw）に置くため整合性をさらに固めたい場合は、Sparkle の
  appcast 署名（`SURequireSignedFeed`）を有効化できます。ただし**リリース工程でフィードを実際に
  署名し、実リリースで検証してから**有効化してください（未署名フィードのまま有効化すると、
  更新自体は届くものの critical 指定・informational・リリースノート/リンクが無効な
  "safe fallback" 動作になります）。
- **サプライチェーン**：CI は Sparkle ツール tarball を **SHA-256 ピン**で検証し、
  `actions/checkout` を **commit SHA ピン**で使用します（更新時は SHA も併せて更新）。

## 構成ファイル

| ファイル | 役割 |
|---|---|
| `Sources/Launchpad/Updater.swift` | Sparkle 配線・gentle reminder・dismiss ガード |
| `Sources/Launchpad/SettingsView.swift` | 「アップデート」欄（手動確認 / 自動トグル / 現在版表示） |
| `Sources/Launchpad/LaunchpadApp.swift` | updater 注入・更新中は自動 dismiss を抑制 |
| `Info.plist` | `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` / `SUScheduledCheckInterval` |
| `build-app.sh` | `Sparkle.framework` 埋め込み + rpath + inside-out 署名 |
| `.github/workflows/release.yml` | `generate_appcast` で署名 appcast を生成・公開 |
| `Package.swift` | Sparkle 2.x 依存 |
