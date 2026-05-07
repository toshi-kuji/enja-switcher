# EnJaSwitcher

## ビルド手順（必ずこの順序で実行）

**重要：必ず `&&` で連結して 1 ブロックとして実行する**。途中の `codesign` が失敗（`errSecInternalComponent` 等）した時に後続の `cp -r ... /Applications/` が走ってしまうと、ad-hoc 署名のままアプリが配置され、TCC 権限が破壊される（後述）。

```bash
pkill -f enja-switcher 2>/dev/null; sleep 2 && \
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit && \
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/ && \
cp Info.plist EnJaSwitcher.app/Contents/ && \
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/ && \
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app && \
codesign -dvv EnJaSwitcher.app 2>&1 | grep -q "Authority=EnJaSwitcher Dev" && \
cp -r EnJaSwitcher.app /Applications/ && \
open /Applications/EnJaSwitcher.app
```

`codesign -dvv ... | grep -q "Authority=EnJaSwitcher Dev"` の検証ステップが本質。これで署名が ad-hoc に落ちていないことを確認してから配置する。

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

### codesign 失敗時の罠

`codesign` が `errSecInternalComponent` 等で失敗した場合（キーチェーンロック、証明書の private key 不可視、等）、コマンドは exit code 非ゼロを返すが、**バイナリには `swiftc` が付与した linker-signed ad-hoc 署名が残ったまま**になる。これに気づかず後続の `cp -r ... /Applications/` を実行してしまうと：

1. ad-hoc 署名された `.app` が `/Applications/` に配置される
2. macOS の TCC が「別物のアプリ」と判定し、アクセシビリティ・入力監視の承認エントリを **破棄**
3. その後正規署名で再ビルド・再配置しても、TCC は既に信頼関係を切っているため **権限を再追加する必要がある**（System Settings から `EnJaSwitcher` をマイナスで削除 → プラスで再追加）

**一度でも ad-hoc を経由すると元の署名で再署名しても権限は自動復活しない**。これは macOS のセキュリティ仕様（一度改変されたバイナリは署名が戻っても信用しない）であり、回避不可能。

### 防止策

ビルドコマンドは必ず `&&` で連結する（上記「ビルド手順」参照）。特に重要なのは：

- `codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app && \` — 失敗時に止まる
- `codesign -dvv EnJaSwitcher.app 2>&1 | grep -q "Authority=EnJaSwitcher Dev" && \` — 署名を検証してから次に進む
- 上記 2 行を通過した後でのみ `cp -r ... /Applications/` を実行する

これにより、`codesign` が失敗した状態で `/Applications/` 配下を上書きすることを防ぐ。

### キーチェーンロックが原因で codesign が失敗する場合

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

でキーチェーンを開いてからビルドし直す（パスワード入力が必要）。または Keychain Access.app で「ログイン」キーチェーンを GUI でロック解除してから再試行。

## 作業上の注意

- commit & push はユーザーが明示的に指示するまで実行しない
- プロジェクトへの変更はユーザーが明示的に指示するまで実行しない
- タスク・TODO 管理は GitHub Issues で行う。`.todo/` や `TODO.md` を新規作成しない
- プランがユーザーに承認されたら、紐づく GitHub Issue にコメントとして全文転記する（紐づく Issue がない場合は作成可否をユーザーに確認）
- GitHub の Issue / PR / コメントにローカルパス（`/Users/...` 等）や個人ディレクトリ構造を書かない

## 重要な制約

- codesign を忘れると入力監視の権限がリセットされる
- `passRetained` を `passUnretained` に変えるとイベントタップが動作しなくなる
- 定数（leftCommandBit, rightCommandBit, commandMask）をクロージャ外のグローバルスコープに移動するとイベントタップが動作しなくなる（Swiftトップレベル実行順序の問題の可能性）
- 日本語IMEのスペースは CGEventTap では介入不可（IMEが先にイベントを消費する）
- macOS 26 では権限キャッシュが壊れることがある → Mac再起動で復活
