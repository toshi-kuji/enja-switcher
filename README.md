# enja-switcher

メニューバーから2つの切り替え方式を選択できるmacOS常駐アプリ（入力ソース切り替えツール）。
メニューバーの「E/J」アイコンから好みの方式を選択できます。

## 目次

- [切り替え方式](#切り替え方式)
- [特徴](#特徴)
- [仕様](#仕様)
- [アプリの構造](#アプリの構造)
- [インストール手順](#インストール手順)
- [ビルド・更新手順（開発者向け）](#ビルド更新手順開発者向け)
- [スタートアップ登録（LaunchAgent）](#スタートアップ登録launchagent)
- [停止方法](#停止方法)
- [アンインストール](#アンインストール)
- [トラブルシューティング](#トラブルシューティング)
- [免責事項](#免責事項)

## 切り替え方式

### 方式1: Left/Right Command（デフォルト）
左右のCommandキーに言語を固定的に割り当てます。
- **左Command 単押し** → 英語（ABC）
- **右Command 単押し** → 日本語（ひらがな）

### 方式2: CapsLock (Single/Double)
1つのキーで状態を気にせず確実に切り替えます。
- **CapsLock 単押し (1回)** → 英語（ABC）
- **CapsLock 二度押し (素早く2回)** → 日本語（ひらがな）

> **CapsLock方式を使用する場合の必須設定**
> macOS標準の「大文字固定」機能（緑のランプ点灯）が競合して誤作動するのを防ぐため、**システム設定 > キーボード > キーボードショートカット > 修飾キー** にて、「Caps Lockキー」への割り当てを必ず **「アクションなし」** に設定してください。（本アプリは独自のハードウェア監視を使用しているため、「アクションなし」に設定しても正確に切り替えが作動します）

## 特徴

- **現在の入力状態を気にせず、目的の言語に直接切り替えられる。** macOS標準の `Ctrl+Space` や `Fn` はトグル式のため「今どちらの言語か」を意識する必要があるが、本ツールではキーと言語が1対1で対応する。
- **外部ライブラリへの依存なし。** `.app` バンドルと LaunchAgent用plist のみで動作し、Karabiner-Elements等の汎用ツールを導入する必要がない。
- **macOSの入力ソース切り替えバグを回避。** macOSには、バックグラウンドからAPI（`TISSelectInputSource`）を用いて日本語入力に切り替えた際、メニューバーのアイコンは変わるものの実際の入力状態が切り替わらないという長年のバグがある。本アプリではシステムAPIではなく**JISキーボードの「英数」キー(102) と「かな」キー(104) の押下イベントを仮想的にエミュレートして送信**する方式を採用し、いかなる状態でも瞬時に確実な切り替えを実現している。

## 仕様

| 項目 | 内容 |
|------|------|
| 対象OS | macOS 13以降（Apple Silicon / Intel） |
| ランタイム依存 | なし（Swift標準ライブラリはOSに内蔵） |
| ビルドツール | `swiftc`（Xcode Command Line Tools） |
| 配布形式 | `.app` バンドル（Dockに表示されないバックグラウンドアプリ） |
| 判定方式 | `CGEventTap` (Command監視) および `IOHIDManager` (CapsLock監視) |
| 設定保存 | `UserDefaults` を用いて選択した切り替え方式を永続化 |
| 切り替え条件 | Commandキー単押し、または CapsLock の単押し/二度押し |
| 他キー併用無視 | Command+C などコンビネーション操作では切り替えが発動しない |
| 入力ソース切替 | 仮想キーコード送信（左Cmd: `102` 英数, 右Cmd: `104` かな） |
| 必要権限 | **アクセシビリティ** および **入力監視** |
| 自動起動の管理 | バックグラウンドでの実行を許可（システム設定 > 一般 > ログイン項目） |

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリを含む `.app` バンドルです。`Info.plist` で `LSUIElement` を指定することで、**Dockにも表示されず、Cmd+Tabにも出ないメニューバー常駐アプリ（Agent App）**として動作します。

### ファイル構成

```
enja-switcher/
  main.swift                          ← ソースコード
  AppIcon.icns                        ← アプリアイコン（ソース）
  EnJaSwitcher.app/
    Contents/
      Info.plist                      ← アプリ設定（バックグラウンド動作指定）
      MacOS/
        enja-switcher                 ← コンパイル済みバイナリ
      Resources/
        AppIcon.icns                  ← アプリアイコン
```

### macOSの権限・管理画面での表示

本アプリは仮想キーの送信とキーボードイベントの読み取りを行うため、macOSのセキュリティ機能により以下の権限が要求されます。

| 表示場所 | 理由 |
|----------|------|
| **システム設定 > プライバシーとセキュリティ > アクセシビリティ** | `CGEvent` を用いて仮想的な「英数/かな」キー押下イベントをシステムに送信（エミュレート）するために必要。 |
| **システム設定 > プライバシーとセキュリティ > 入力監視** | `CGEventTap`（Command監視）および `IOHIDManager`（CapsLock監視）でキーボードの入力状態を読み取るために必要。 |
| **システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** | LaunchAgent plist による自動起動が登録されていることを示す。macOS 13以降、LaunchAgentで登録されたプロセスはここに表示される。 |

## インストール手順

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

### ステップ 3: 自己署名証明書の作成

アプリの更新時にmacOSの権限（アクセシビリティ・入力監視）を再設定する手間をなくすため、自己署名証明書で署名します。同じ証明書で署名し続ける限り、再ビルド後も権限は維持されます。

**Keychain Access で証明書を作成する手順:**

1. **Keychain Access** アプリを開く（Spotlight で「Keychain Access」と検索）
2. メニューバーから **Keychain Access > 証明書アシスタント > 証明書を作成...** を選択
3. 以下の設定で作成:
   - **名前**: `EnJaSwitcher Dev`
   - **固有名のタイプ**: 自己署名ルート
   - **証明書のタイプ**: コード署名
4. 「作成」をクリック

> この手順は初回の1回だけ実行すれば十分です。作成した証明書はKeychainに保存され、以降のビルドで繰り返し使用できます。

### ステップ 4: ビルド・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/Resources
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

### ステップ 5: 初回起動と権限の付与

```bash
open /Applications/EnJaSwitcher.app
```

初回起動時にmacOSのダイアログが表示されます。**システム設定 > プライバシーとセキュリティ** を開き、以下の2箇所で `EnJaSwitcher` を許可（オン）してください：

- **アクセシビリティ**（仮想キー送信に必要）
- **入力監視**（キーボード監視に必要）

> **重要**: 必ず `.app` として起動してください。ターミナルからバイナリを直接実行すると、権限がTerminal.appに付与されてしまい正しく動作しません。

### ステップ 6: 動作確認

- **左Command 単押し** → 英語（ABC）に切り替わる
- **右Command 単押し** → 日本語（ひらがな）に切り替わる

これでインストール完了です。ログイン時に自動起動させたい場合は「[スタートアップ登録（LaunchAgent）](#スタートアップ登録launchagent)」を参照してください。

## ビルド・更新手順（開発者向け）

コードを変更した後や、アプリを更新する際は以下の手順を実行します。

### 実行中のアプリを停止

```bash
pkill -f enja-switcher
```

### コンパイル・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/Resources
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
rm -rf /Applications/EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

### 起動

```bash
open /Applications/EnJaSwitcher.app
```

> **署名と権限について**
> インストール時に作成した自己署名証明書（`EnJaSwitcher Dev`）で署名している限り、再ビルド後もmacOSのセキュリティ権限（アクセシビリティ・入力監視）は**再設定不要**です。macOSの TCC データベースは署名の identity でアプリを識別するため、同じ証明書で署名されたバイナリは「同じアプリ」として扱われます。
>
> **注意**: 証明書を作り直した場合や、異なる署名でビルドした場合は、権限の再設定が必要です。システム設定 > プライバシーとセキュリティ から「アクセシビリティ」と「入力監視」の両方で、`EnJaSwitcher` を**マイナスボタンで削除してからプラスボタンで再追加**してください。

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

> **補足**: LaunchAgentはlaunchdがバイナリを直接起動するため、Terminal.app経由ではありません。権限は正しく `EnJaSwitcher.app` に対して適用されます。

全ユーザー共通にする場合は、配置先を `/Library/LaunchAgents/` に変更し `sudo` を使用して作成してください。ただし、セキュリティ権限（アクセシビリティと入力監視）は各ユーザーで個別に許可する必要があります。

## 停止方法

メニューバーの「E/J」アイコンをクリックし、**「Quit EnJaSwitcher」** を選択して終了します。

メニューが反応しない場合は、以下の方法で強制終了できます。

### アクティビティモニタから停止

1. アクティビティモニタを開く
2. 検索欄で「enja」と入力
3. `enja-switcher` を選択して「×」ボタンで終了

### ターミナルから停止

```bash
pkill -f enja-switcher
```

## アンインストール

本アプリを完全にシステムから削除するには、以下の手順を実行してください。

### ステップ 1: アプリプロセスの終了

メニューバーから終了するか、以下のコマンドで強制終了します。
```bash
pkill -f enja-switcher
```

### ステップ 2: 自動起動設定の削除

```bash
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

### ステップ 3: アプリケーション本体の削除

```bash
rm -rf /Applications/EnJaSwitcher.app
```

### ステップ 4: セキュリティ権限のクリーンアップ（手動）

アプリ本体を削除しても、macOSの設定画面には古い権限情報が残ります。
1. **システム設定 > プライバシーとセキュリティ** を開く。
2. **アクセシビリティ** のリストに `EnJaSwitcher` があれば、**「ー（マイナス）」** ボタンで削除。
3. 同様に、**入力監視** のリストからも削除。

## トラブルシューティング

| 症状 | 対処法 |
|------|--------|
| **ターミナル内では動くが、他のアプリで動かない** | macOSの権限ブロックが原因。「アクセシビリティ」と「入力監視」のリストから `EnJaSwitcher` を**マイナスボタンで削除し、プラスボタンで再追加**する。 |
| **切り替えが動かない** | 権限のリセット（上記）を試す。`open /Applications/EnJaSwitcher.app` で起動しているか確認。 |
| **ログイン後に起動しない** | `launchctl list \| grep enja` でプロセス状態を確認。plistファイルが正しい場所に存在するか確認。 |
| **ビルド後に切り替えが動かなくなった** | `codesign -dvv /Applications/EnJaSwitcher.app` で署名情報を確認。自己署名証明書（`EnJaSwitcher Dev`）で署名されていない場合は、「アクセシビリティ」と「入力監視」からマイナスで削除して再追加。 |

## 免責事項

- 本アプリは個人利用を想定した自作ツールであり、動作保証はありません。
- 自己署名証明書はローカル環境でのみ有効です。Apple公証（Notarization）を受けていないため、他のMacへの配布には適しません。
- `CGEventTap` によるキーボードイベントの監視は、macOSのセキュリティポリシーの変更により将来動作しなくなる可能性があります。
- 権限はmacOSが管理しており、本アプリがキー入力の内容を記録・送信することはありません。
