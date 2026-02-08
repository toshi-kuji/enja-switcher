# enja-switcher

Commandキーの単押しで入力ソース（英語/日本語）を切り替えるmacOS常駐アプリ。

- **左Command** → 英語（ABC）
- **右Command** → 日本語（ひらがな）

## 狙い

macOSの入力ソース切り替えは `Ctrl+Space` や `Fn` など複数の方法があるが、いずれも「今どちらの言語か」を意識してトグルする必要がある。本ツールは左右のCommandキーに言語を固定的に割り当てることで、**現在の状態を気にせず確実に目的の言語に切り替える**ことを実現する。

Karabiner-Elementsなどの汎用ツールでも同等の設定は可能だが、本ツールは `.app` バンドルと LaunchAgent用plist のみで動作し、外部ライブラリへの依存なしで軽量に運用できる。

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリであり、UIのコードは一切含まない。バイナリをそのまま実行するとターミナルウィンドウが開いてしまうため、`.app` バンドルで包み、`Info.plist` で `LSBackgroundOnly` と `LSUIElement` を指定することで、**ターミナルを開かず、Dockにも表示されず、Cmd+Tabにも出ない、完全に見えないバックグラウンドプロセス**として動作させている。

このため、アプリの停止にはアクティビティモニタまたはターミナルからのコマンド操作が必要になる（後述「停止方法」を参照）。

初回起動時に入力監視の権限が未付与の場合、macOSの権限ダイアログを自動で表示し、権限が付与されるまで待機する。この権限ダイアログはmacOS側が表示するものであり、アプリ自体にUIは含まない。

### macOSの権限・管理画面での表示

本アプリは以下の2箇所に表示される。いずれも正常な状態であり、それぞれ役割が異なる。

| 表示場所 | 理由 |
|----------|------|
| **システム設定 > プライバシーとセキュリティ > 入力監視** | `CGEventTap` でキーボードイベントを読み取るために必要な権限。ユーザーが明示的に許可する。 |
| **システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** | LaunchAgent plist による自動起動が登録されていることを示す。macOS 13以降、LaunchAgentで登録されたプロセスはここに表示される。 |

「ログイン項目」の「Open at Login」欄には表示されない。Open at Login は `SMAppService` 等で登録されたアプリ用であり、LaunchAgent方式の本アプリは「バックグラウンドでの実行を許可」側に分類される。

## 仕様

| 項目 | 内容 |
|------|------|
| 対象OS | macOS 13以降（Apple Silicon / Intel） |
| ランタイム依存 | なし（Swift標準ライブラリはOSに内蔵） |
| ビルドツール | `swiftc`（Xcode Command Line Tools） |
| 配布形式 | `.app` バンドル（Dockに表示されないバックグラウンドアプリ） |
| 判定方式 | `CGEventTap` で修飾キーイベントを監視 |
| 左右判別 | `CGEventFlags` の rawValue ビットマスク（左: `0x08`, 右: `0x10`） |
| 切り替え条件 | Commandキーを単独で押して離したとき（単押し） |
| 他キー併用無視 | Command+C などコンビネーション操作では切り替えが発動しない |
| 入力ソース切替 | `TISCopyInputSourceForLanguage` + `TISSelectInputSource` |
| 権限チェック | `CGEvent.tapCreate` の成否で判定、未付与なら `AXIsProcessTrustedWithOptions` で設定画面を自動表示 |
| 必要権限 | 入力監視（システム設定 > プライバシーとセキュリティ > 入力監視） |
| 自動起動の管理 | バックグラウンドでの実行を許可（システム設定 > 一般 > ログイン項目） |
| LaunchAgent配置先 | `/Library/LaunchAgents/`（全ユーザー共通、入力監視の権限は各ユーザーで個別に許可） |

## ファイル構成

```
enja-switcher/
  main.swift                          ← ソースコード
  EnJaSwitcher.app/
    Contents/
      Info.plist                      ← アプリ設定（バックグラウンド動作指定）
      MacOS/
        enja-switcher                 ← コンパイル済みバイナリ
```

## ビルド

### 前提

Xcode Command Line Toolsがインストールされていること：

```bash
xcode-select --install
```

### コンパイル・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign - EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

ソースを変更した場合は上記のコマンドをすべて再実行する。

> **重要: `codesign` を必ず実行すること。** 未署名のバイナリはコンパイルのたびにハッシュが変わり、macOSが「別のアプリ」と認識して入力監視の権限をリセットする。`codesign --force --sign -`（ad-hoc署名）を実行すれば、macOSが同一アプリとして認識し続けるため、権限の再設定は不要になる。Apple Developer Program（有料）への加入は不要。

### AIにビルドを指示する場合

Claude Code等のAIツールにビルドを依頼する場合は、以下のように指示する：

```
main.swiftをコンパイルし、署名し、/Applications/ に配置して、プロセスを再起動してください。
手順：
1. pkill -f enja-switcher
2. swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa
3. cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
4. codesign --force --sign - EnJaSwitcher.app
5. cp -r EnJaSwitcher.app /Applications/
6. open /Applications/EnJaSwitcher.app
```

**codesignを忘れると入力監視の権限が無効化され、再度手動で権限を付与し直す必要がある。**

## インストールと初回セットアップ

### 1. アプリを `/Applications/` に配置

```bash
cp -r EnJaSwitcher.app /Applications/
```

### 2. 初回起動して入力監視の権限を付与

Finderで `/Applications/EnJaSwitcher.app` をダブルクリック、またはターミナルで：

```bash
open /Applications/EnJaSwitcher.app
```

初回起動時に入力監視の権限ダイアログが自動で表示される。**システム設定 > プライバシーとセキュリティ > 入力監視** で `EnJaSwitcher` を許可すると動作を開始する。

**重要**: 必ず `.app` として起動すること。ターミナルからバイナリ（`EnJaSwitcher.app/Contents/MacOS/enja-switcher`）を直接実行すると、権限がTerminal.appに対して付与されてしまい、アプリ自体には権限が付かない。

### 3. 動作確認

左Commandを単押し → 英語、右Commandを単押し → 日本語に切り替わることを確認する。

## Info.plist

`EnJaSwitcher.app/Contents/Info.plist` の内容（同梱済み）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.enja-switcher</string>
    <key>CFBundleName</key>
    <string>EnJaSwitcher</string>
    <key>CFBundleExecutable</key>
    <string>enja-switcher</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- **LSBackgroundOnly**: UIを持たないバックグラウンドプロセスとして起動する（ターミナルウィンドウが開かない）
- **LSUIElement**: Dockやアプリケーションスイッチャー（Cmd+Tab）に表示しない

## スタートアップ登録（LaunchAgent）

ログイン時に自動起動させるには、LaunchAgent用のplistファイルを `/Library/LaunchAgents/`（システム全体）に作成する。この場所に配置すると、**このMacにログインするすべてのユーザーに対して自動起動される**。アプリは前述の手順で `/Applications/` に配置済みであること。

> **注意**: 入力監視の権限はユーザーごとに個別に許可が必要。新しいユーザーで初めてログインした際に権限ダイアログが表示される。

### plistを作成

```bash
sudo tee /Library/LaunchAgents/com.local.enja-switcher.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.enja-switcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/EnJaSwitcher.app/Contents/MacOS/enja-switcher</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
```

上記の手順だけで、次回ログイン時から自動起動される。plistを作成すると、**システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** に `enja-switcher` が表示される（macOS 13以降）。

### 再ログインせず今すぐ起動したい場合

```bash
launchctl load /Library/LaunchAgents/com.local.enja-switcher.plist
```

`launchctl load` はplistをシステムに読み込ませて即座にプロセスを起動するコマンドであり、スタートアップ登録そのものではない。plistファイルが `/Library/LaunchAgents/` に存在すれば、次回ログイン時にmacOSが自動で読み込む。`/Library/LaunchAgents/` への配置には `sudo` が必要だが、`launchctl load` はユーザーセッションで実行するため `sudo` 不要。

## 停止方法

本アプリはUIを持たない見えないプロセスのため、停止にはアクティビティモニタかターミナル操作が必要。

### アクティビティモニタから停止

1. アクティビティモニタを開く
2. 検索欄で「enja」と入力
3. `enja-switcher` を選択して「×」ボタンで終了

### ターミナルから停止

```bash
pkill -f enja-switcher
```

`pkill` やアクティビティモニタで停止したプロセスは、次回ログイン時に `RunAtLoad` により再び自動起動される。永続的にスタートアップから外すにはplistファイルを削除する：

```bash
sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
```

## アンインストール

```bash
pkill -f enja-switcher
launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist
sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
rm -rf /Applications/EnJaSwitcher.app
```

以下も手動で確認・削除する：

- **入力監視**: システム設定 > プライバシーとセキュリティ > 入力監視 から `EnJaSwitcher` を削除
- **バックグラウンドアクティビティ**: plist削除後、システム設定 > 一般 > ログイン項目 から `enja-switcher` が消えていることを確認

## トラブルシューティング

- **切り替えが動かない** → 入力監視の権限を確認（システム設定 > プライバシーとセキュリティ > 入力監視）。`open EnJaSwitcher.app` で直接起動して動作するか試す。
- **権限付与後も動かない** → 一度入力監視のリストから `EnJaSwitcher` を削除して再追加する。
- **ログイン後に起動しない** → `launchctl list | grep enja` でプロセス状態を確認。plistファイルが `/Library/LaunchAgents/` に存在するか確認。
- **ターミナルが起動する** → `.app` バンドルの `Info.plist` に `LSBackgroundOnly` が設定されているか確認。
- **`launchctl load` で `Input/output error`** → 既にplistが読み込み済み。`launchctl unload` してから再度 `load` する。
- **ビルド後に切り替えが動かなくなった** → `codesign --force --sign - EnJaSwitcher.app` を実行せずにバイナリを入れ替えた可能性が高い。入力監視のリストから削除して再追加するか、codesignしてから再配置する。

## 免責事項

- 本アプリは個人利用を想定した自作ツールであり、動作保証はない。
- ad-hoc署名（`codesign --force --sign -`）はローカル環境でのみ有効であり、Apple公証（Notarization）を受けていないため、他のMacへの配布には適さない。
- `CGEventTap` によるキーボードイベントの監視は、macOSのセキュリティポリシーの変更により将来動作しなくなる可能性がある。
- 入力監視の権限はmacOSがユーザー単位で管理しており、本アプリがキー入力の内容を記録・送信することはない。
