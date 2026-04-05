# enja-switcher

メニューバーから2つの切り替え方式を選択できるmacOS常駐アプリ（入力ソース切り替えツール）。
メニューバーの「E/J」アイコンから好みの方式を選択できます。

### 方式1: Left/Right Command（デフォルト）
左右のCommandキーに言語を固定的に割り当てます。
- **左Command 単押し** → 英語（ABC）
- **右Command 単押し** → 日本語（ひらがな）

### 方式2: CapsLock (Single/Double)
1つのキーで状態を気にせず確実に切り替えます。
- **CapsLock 単押し (1回)** → 英語（ABC）
- **CapsLock 二度押し (素早く2回)** → 日本語（ひらがな）
> **⚠️ CapsLock方式を使用する場合の必須設定**
> macOS標準の「大文字固定」機能（緑のランプ点灯）が競合して誤作動するのを防ぐため、**システム設定 ＞ キーボード ＞ キーボードショートカット ＞ 修飾キー** にて、「Caps Lockキー」への割り当てを必ず **「アクションなし」** に設定してご使用ください。（※本アプリは独自のハードウェア監視を使用しているため、「アクションなし」に設定しても正確に切り替えが作動します）

## 狙い

macOSの入力ソース切り替えは `Ctrl+Space` や `Fn` など複数の方法があるが、いずれも「今どちらの言語か」を意識してトグルする必要がある。本ツールは左右のCommandキーに言語を固定的に割り当てることで、**現在の状態を気にせず確実に目的の言語に切り替える**ことを実現する。

Karabiner-Elementsなどの汎用ツールでも同等の設定は可能だが、本ツールは `.app` バンドルと LaunchAgent用plist のみで動作し、外部ライブラリへの依存なしで軽量に運用できる。

### macOSの入力ソース切り替えバグへの対応
macOSには、バックグラウンドからAPI（`TISSelectInputSource`）を用いて日本語入力に切り替えた際、メニューバーのアイコンは変わるものの実際の入力状態が切り替わらない（アプリを切り替えるまで反映されない）という長年のバグが存在します。
本アプリではこれを回避するため、システムAPIではなく**JISキーボードの「英数」キー(102) と「かな」キー(104) の押下イベントを仮想的にエミュレートして送信**する方式を採用しています。これにより、いかなる状態でも瞬時に確実な切り替えが可能になっています。

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリを含む `.app` バンドルです。`Info.plist` で `LSUIElement` を指定することで、**Dockにも表示されず、Cmd+Tabにも出ないメニューバー常駐アプリ（Agent App）**として動作させています。

アプリの停止は、メニューバーの「E/J」アイコンから「Quit EnJaSwitcher」を選択するか、アクティビティモニタ等から行うことができます。

### macOSの権限・管理画面での表示

本アプリは仮想キーの送信とキーボードイベントの読み取りを行うため、macOSの強固なセキュリティ機能により以下の権限が要求されます。

| 表示場所 | 理由 |
|----------|------|
| **システム設定 > プライバシーとセキュリティ > アクセシビリティ** | `CGEvent` を用いて仮想的な「英数/かな」キー押下イベントをシステムに送信（エミュレート）するために必要。 |
| **システム設定 > プライバシーとセキュリティ > 入力監視** | `CGEventTap`（Command監視）および `IOHIDManager`（CapsLock監視）でキーボードの入力状態を読み取るために必要。 |
| **システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** | LaunchAgent plist による自動起動が登録されていることを示す。macOS 13以降、LaunchAgentで登録されたプロセスはここに表示される。 |

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

### ステップ 3: 自己署名証明書の作成（初回のみ）

アプリの更新時にmacOSの権限（アクセシビリティ・入力監視）を再設定する手間をなくすため、自己署名証明書で署名します。ad-hoc署名（`--sign -`）ではビルドごとにハッシュが変わり、macOSが「別のアプリ」と判断して権限がリセットされますが、同じ証明書で署名し続ける限り権限は維持されます。

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

### ステップ 5: 初回起動して権限を付与

```bash
open /Applications/EnJaSwitcher.app
```

初回起動時にmacOSのダイアログが表示されます。**システム設定 > プライバシーとセキュリティ** を開き、以下の2箇所で `EnJaSwitcher` を許可（オン）してください：

- **アクセシビリティ**（仮想キー送信に必要）
- **入力監視**（Commandキー監視に必要）

> **重要**: 必ず `.app` として起動してください。ターミナルからバイナリを直接実行すると、権限がTerminal.appに付与されてしまい正しく動作しません。

### ステップ 6: 動作確認

- **左Command 単押し** → 英語（ABC）に切り替わる
- **右Command 単押し** → 日本語（ひらがな）に切り替わる

これでインストール完了です。次回以降のログイン時も手動で起動が必要な場合は、「スタートアップ登録」セクションを参照してください。

---

## ビルドとアプリ更新時の手順

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

> **自己署名証明書による権限維持について**
> 初回セットアップで作成した自己署名証明書（`EnJaSwitcher Dev`）で署名している限り、再ビルド・アップデート後もmacOSのセキュリティ権限（アクセシビリティ・入力監視）は**再設定不要**です。macOSの TCC データベースは署名の identity でアプリを識別するため、同じ証明書で署名されたバイナリは「同じアプリ」として扱われます。
>
> **注意**: もし証明書を作り直した場合や、ad-hoc署名（`--sign -`）でビルドした場合は、権限の再設定が必要になります。その場合は以下の手順で権限をリセットしてください：
> 1. システム設定 > プライバシーとセキュリティ > **アクセシビリティ** を開く。
> 2. リスト内の `EnJaSwitcher` を選択し、下の **「ー（マイナス）」ボタンを押して完全に削除**する。
> 3. 下の **「＋（プラス）」ボタンを押し**、`/Applications/EnJaSwitcher.app` を選択して追加し直す。
> 4. システム設定 > プライバシーとセキュリティ > **入力監視** でも、同様に **「ー」で削除してから「＋」で追加**を行う。

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

メニューバーの「E/J」アイコンをクリックし、**「Quit EnJaSwitcher」** を選択して終了します。

何らかの理由でメニューが反応しない場合は、以下の方法で強制終了できます。

### アクティビティモニタから停止

1. アクティビティモニタを開く
2. 検索欄で「enja」と入力
3. `enja-switcher` を選択して「×」ボタンで終了

### ターミナルから停止

```bash
pkill -f enja-switcher
```

## 完全なアンインストール手順

本アプリ（旧バージョンを含む）を完全にシステムから削除するには、以下の手順を実行してください。

### ステップ 1: アプリプロセスの終了
メニューバーから終了するか、以下のコマンドで強制終了します。
```bash
pkill -f enja-switcher
```

### ステップ 2: 自動起動（LaunchAgent）設定の削除
```bash
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

### ステップ 3: アプリケーション本体の削除
```bash
rm -rf /Applications/EnJaSwitcher.app
```

### ステップ 4: macOSのセキュリティ権限のクリーンアップ（手動）
アプリ本体を削除しても、macOSの設定画面には古い権限情報が残るため、以下の手順で手動削除します。
1. **システム設定 ＞ プライバシーとセキュリティ** を開く。
2. **アクセシビリティ** をクリックし、リストの中に `EnJaSwitcher` があれば選択して下の **「ー（マイナス）」** ボタンを押して削除します。
3. 同様に、**入力監視** のリストからも `EnJaSwitcher` を削除します。

これで完全なアンインストールは完了です。

## トラブルシューティング

- **ターミナル内では動くが、他のアプリで動かない** → macOSの権限ブロックが原因です。「アクセシビリティ」と「入力監視」のリストから `EnJaSwitcher` を**マイナスボタンで削除し、プラスボタンで再追加**してください。
- **切り替えが動かない** → 権限のリセットを試してください。それでも駄目な場合は `open /Applications/EnJaSwitcher.app` で起動しているか確認してください。
- **ログイン後に起動しない** → `launchctl list | grep enja` でプロセス状態を確認。plistファイルが正しい場所に存在するか確認。
- **ビルド後に切り替えが動かなくなった** → 自己署名証明書（`EnJaSwitcher Dev`）で署名されているか確認してください。`codesign -dvv /Applications/EnJaSwitcher.app` で署名情報を確認できます。ad-hoc署名（`--sign -`）や異なる証明書で署名した場合は、「アクセシビリティ」と「入力監視」からマイナスボタンで削除して再追加してください。

## 免責事項

- 本アプリは個人利用を想定した自作ツールであり、動作保証はない。
- 自己署名証明書（`codesign --force --sign "EnJaSwitcher Dev"`）はローカル環境でのみ有効であり、Apple公証（Notarization）を受けていないため、他のMacへの配布には適さない。
- `CGEventTap` によるキーボードイベントの監視は、macOSのセキュリティポリシーの変更により将来動作しなくなる可能性がある。
- 権限はmacOSが管理しており、本アプリがキー入力の内容を記録・送信することはない。
