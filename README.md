# enja-switcher

Commandキーの単押しで入力ソース（英語/日本語）を切り替えるmacOS常駐アプリ。

- **左Command** → 英語（ABC）
- **右Command** → 日本語（ひらがな）

## 狙い

macOSの入力ソース切り替えは `Ctrl+Space` や `Fn` など複数の方法があるが、いずれも「今どちらの言語か」を意識してトグルする必要がある。本ツールは左右のCommandキーに言語を固定的に割り当てることで、**現在の状態を気にせず確実に目的の言語に切り替える**ことを実現する。

Karabiner-Elementsなどの汎用ツールでも同等の設定は可能だが、本ツールは `.app` バンドルと LaunchAgent用plist のみで動作し、外部ライブラリへの依存なしで軽量に運用できる。

### macOSの入力ソース切り替えバグへの対応
macOSには、バックグラウンドからAPI（`TISSelectInputSource`）を用いて日本語入力に切り替えた際、メニューバーのアイコンは変わるものの実際の入力状態が切り替わらない（アプリを切り替えるまで反映されない）という長年のバグが存在します。
本アプリではこれを回避するため、システムAPIではなく**JISキーボードの「英数」キー(102) と「かな」キー(104) の押下イベントを仮想的にエミュレートして送信**する方式を採用しています。これにより、いかなる状態でも瞬時に確実な切り替えが可能になっています。

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリであり、UIのコードは一切含まない。バイナリをそのまま実行するとターミナルウィンドウが開いてしまうため、`.app` バンドルで包み、`Info.plist` で `LSBackgroundOnly` と `LSUIElement` を指定することで、**ターミナルを開かず、Dockにも表示されず、Cmd+Tabにも出ない、完全に見えないバックグラウンドプロセス**として動作させている。

このため、アプリの停止にはアクティビティモニタまたはターミナルからのコマンド操作が必要になる（後述「停止方法」を参照）。

### macOSの権限・管理画面での表示

本アプリは仮想キーの送信とキーボードイベントの読み取りを行うため、macOSの強固なセキュリティ機能により以下の権限が要求されます。

| 表示場所 | 理由 |
|----------|------|
| **システム設定 > プライバシーとセキュリティ > アクセシビリティ** | `CGEvent` を用いて仮想的な「英数/かな」キー押下イベントをシステムに送信（エミュレート）するために必要。 |
| **システム設定 > プライバシーとセキュリティ > 入力監視** | `CGEventTap` でキーボードのCommandキー単押しを監視・読み取るために必要。 |
| **システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** | LaunchAgent plist による自動起動が登録されていることを示す。macOS 13以降、LaunchAgentで登録されたプロセスはここに表示される。 |

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
| 入力ソース切替 | 仮想キーコード送信（左Cmd: `102` 英数, 右Cmd: `104` かな） |
| 必要権限 | **アクセシビリティ** および **入力監視** |
| 自動起動の管理 | バックグラウンドでの実行を許可（システム設定 > 一般 > ログイン項目） |

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

## インストール手順（初回）

初めて使用する場合は、以下の手順を順番に実行してください。

### ステップ 1: 前提条件の確認

Xcode Command Line Tools がインストールされていることを確認します。

```bash
xcode-select --version
```

インストールされていない場合：

```bash
xcode-select --install
```

### ステップ 2: リポジトリのクローン

```bash
git clone https://github.com/toshi-kuji/enja-switcher.git
cd enja-switcher
```

### ステップ 3: ビルド・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign - EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

### ステップ 4: 初回起動して権限を付与

```bash
open /Applications/EnJaSwitcher.app
```

初回起動時にmacOSのダイアログが表示されます。**システム設定 > プライバシーとセキュリティ** を開き、以下の2箇所で `EnJaSwitcher` を許可（オン）してください：

- **アクセシビリティ**（仮想キー送信に必要）
- **入力監視**（Commandキー監視に必要）

> **重要**: 必ず `.app` として起動してください。ターミナルからバイナリを直接実行すると、権限がTerminal.appに付与されてしまい正しく動作しません。

### ステップ 5: 動作確認

- **左Command 単押し** → 英語（ABC）に切り替わる
- **右Command 単押し** → 日本語（ひらがな）に切り替わる

これでインストール完了です。次回以降のログイン時も手動で起動が必要な場合は、「スタートアップ登録」セクションを参照してください。

---

## ビルドとアプリ更新時の注意（重要）

### コンパイル・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign - EnJaSwitcher.app
rm -rf /Applications/EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

> **セキュリティ権限の完全リセットについて（アップデート時）**
> バイナリを再コンパイルして `/Applications/` に上書き配置した場合、macOSはこれを「過去に許可したものとは別の新しいアプリ」と見なし、**バックグラウンドでの動作をサイレントにブロック**します。
> この状態になると、権限画面でスイッチが「オン」になっていても動作しません。
>
> アプリを更新（再ビルド）した際は、必ず以下の手順で権限を**完全リセット**してください：
> 1. システム設定 > プライバシーとセキュリティ > **アクセシビリティ** を開く。
> 2. リスト内の `EnJaSwitcher` を選択し、下の **「ー（マイナス）」ボタンを押して完全に削除**する。
> 3. 下の **「＋（プラス）」ボタンを押し**、`/Applications/EnJaSwitcher.app` を選択して追加し直す。
> 4. システム設定 > プライバシーとセキュリティ > **入力監視** でも、同様に **「ー」で削除してから「＋」で追加**を行う。
>
> スイッチのオフ/オンだけでは古いキャッシュが残りブロックされ続けるため、必ず「マイナスで削除してプラスで追加」を行ってください。

## スタートアップ登録（LaunchAgent）

ログイン時に自動起動させるには、LaunchAgent用のplistファイルを作成します。

**現在のユーザーのみ自動起動させる場合:**
```bash
mkdir -p ~/Library/LaunchAgents
cat << 'EOF' > ~/Library/LaunchAgents/com.local.enja-switcher.plist
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
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

※ 全ユーザー共通にする場合は、配置先を `/Library/LaunchAgents/` に変更し `sudo` を使用して作成してください。ただし、セキュリティ権限（アクセシビリティと入力監視）は各ユーザーで初めてログインした際に個別に許可・追加する必要があります。

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

## アンインストール

```bash
pkill -f enja-switcher
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist
rm ~/Library/LaunchAgents/com.local.enja-switcher.plist
rm -rf /Applications/EnJaSwitcher.app
```

以下も手動で確認・削除する：
- **アクセシビリティ・入力監視**: システム設定 > プライバシーとセキュリティ から `EnJaSwitcher` をマイナスボタンで削除

## トラブルシューティング

- **ターミナル内では動くが、他のアプリで動かない** → macOSの権限ブロックが原因です。「アクセシビリティ」と「入力監視」のリストから `EnJaSwitcher` を**マイナスボタンで削除し、プラスボタンで再追加**してください。
- **切り替えが動かない** → 権限のリセットを試してください。それでも駄目な場合は `open /Applications/EnJaSwitcher.app` で起動しているか確認してください。
- **ログイン後に起動しない** → `launchctl list | grep enja` でプロセス状態を確認。plistファイルが正しい場所に存在するか確認。
- **ビルド後に切り替えが動かなくなった** → 未署名、もしくは更新により別のアプリと判定されています。「アクセシビリティ」と「入力監視」からマイナスボタンで削除して再追加してください。

## 免責事項

- 本アプリは個人利用を想定した自作ツールであり、動作保証はない。
- ad-hoc署名（`codesign --force --sign -`）はローカル環境でのみ有効であり、Apple公証（Notarization）を受けていないため、他のMacへの配布には適さない。
- `CGEventTap` によるキーボードイベントの監視は、macOSのセキュリティポリシーの変更により将来動作しなくなる可能性がある。
- 権限はmacOSが管理しており、本アプリがキー入力の内容を記録・送信することはない。
