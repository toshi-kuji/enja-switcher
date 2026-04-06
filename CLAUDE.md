# EnJaSwitcher

## ビルド手順（必ずこの順序で実行）

```bash
pkill -f enja-switcher && sleep 2
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
open /Applications/EnJaSwitcher.app
```

## リリース手順

1. `Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を新バージョンに更新（必ず `X.Y.Z` の3桁形式。GitHub Release タグも `vX.Y.Z` で統一。桁数が異なると `.compare(_, options: .numeric)` で誤判定が起きる）
2. ビルド（上記手順）→ 動作確認
3. `EnJaSwitcher.app` を zip に固める
4. GitHub で新しい Release を作成（tag 例: `v1.1.0`）、zip をアップロード
5. ウェブサイトは GitHub Actions が自動で再デプロイする（`release: published` トリガー）
   - ビルド時に GitHub Releases API から最新バージョンを取得してダウンロードボタンに反映
   - i18n にバージョンをハードコードする必要はない

## 署名について

- **絶対に ad-hoc 署名（`--sign -`）を使わないこと**。開発機に固定の自己署名証明書「EnJaSwitcher Dev」がインストールされている
- 常に `codesign --force --sign "EnJaSwitcher Dev"` を使う。ad-hoc にすると署名 identity が変わり、macOS が別アプリとみなして入力監視・アクセシビリティの権限がリセットされる
- 同じ証明書で署名し続ける限り、再ビルドしても権限は維持される

## 作業上の注意

- commit & push はユーザーが明示的に指示するまで実行しない

## 重要な制約

- codesign を忘れると入力監視の権限がリセットされる
- `passRetained` を `passUnretained` に変えるとイベントタップが動作しなくなる
- 定数（leftCommandBit, rightCommandBit, commandMask）をクロージャ外のグローバルスコープに移動するとイベントタップが動作しなくなる（Swiftトップレベル実行順序の問題の可能性）
- 日本語IMEのスペースは CGEventTap では介入不可（IMEが先にイベントを消費する）
- macOS 26 では権限キャッシュが壊れることがある → Mac再起動で復活
