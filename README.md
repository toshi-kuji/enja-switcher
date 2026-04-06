# enja-switcher

- [English](#enja-switcher-english)
- [日本語](#enja-switcher日本語)

---

# enja-switcher (English)

A macOS menu bar resident app (input source switcher) that lets you choose between two switching methods from the menu bar. Select your preferred method from the "E/J" icon in the menu bar.

## Table of Contents

- [Switching Methods](#switching-methods)
- [Features](#features)
- [Specifications](#specifications)
- [App Structure](#app-structure)
- [Installation](#installation)
- [Build & Update (For Developers)](#build--update-for-developers)
- [Startup Registration (LaunchAgent)](#startup-registration-launchagent)
- [How to Stop](#how-to-stop)
- [Uninstallation](#uninstallation)
- [Troubleshooting](#troubleshooting)
- [Gatekeeper & Security Notes](#gatekeeper--security-notes)
- [Disclaimer](#disclaimer)

## Switching Methods

### Method 1: Left/Right Command (Default)
Assigns a fixed language to each Command key.
- **Left Command single press** → English (ABC)
- **Right Command single press** → Japanese (Hiragana)

### Method 2: CapsLock (Single/Double)
Reliably switches languages with a single key, regardless of the current state.
- **CapsLock single press (once)** → English (ABC)
- **CapsLock double press (quickly twice)** → Japanese (Hiragana)

> **Required setting when using the CapsLock method**
> To prevent conflicts with macOS's built-in "Caps Lock" function (green light on), go to **System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys** and set the "Caps Lock key" assignment to **"No Action"**. (Since this app uses its own hardware monitoring, the switching will work correctly even with the "No Action" setting.)

## Features

- **Switch directly to the desired language without worrying about the current input state.** macOS's standard `Ctrl+Space` or `Fn` are toggle-based, requiring you to be aware of the current language. With this tool, each key maps directly to one language.
- **No external library dependencies.** Runs with only the `.app` bundle and a LaunchAgent plist file, eliminating the need to install general-purpose tools like Karabiner-Elements.
- **Works around macOS's input source switching bug.** macOS has a long-standing bug where switching to Japanese input from the background via the API (`TISSelectInputSource`) changes the menu bar icon but not the actual input state. This app uses **virtual emulation of JIS keyboard "Eisuu" key (102) and "Kana" key (104) press events** instead of the system API, achieving instant and reliable switching in any state.

## Specifications

| Item | Details |
|------|---------|
| Target OS | macOS 13 or later (Apple Silicon / Intel) |
| Runtime dependency | None (Swift standard library is built into the OS) |
| Build tool | `swiftc` (Xcode Command Line Tools) |
| Distribution format | `.app` bundle (background app that does not appear in the Dock) |
| Detection method | `CGEventTap` (Command monitoring) and `IOHIDManager` (CapsLock monitoring) |
| Settings persistence | Saves the selected switching method using `UserDefaults` |
| Switching condition | Command key single press, or CapsLock single/double press |
| Combination key ignored | Switching does not trigger during combination operations such as Command+C |
| Input source switching | Virtual keycode dispatch (Left Cmd: `102` Eisuu, Right Cmd: `104` Kana) |
| Required permissions | **Accessibility** and **Input Monitoring** |
| Update check | Periodically checks GitHub Releases API for new versions. No personal data is sent. Can be disabled from the menu bar. |
| Auto-start management | Allow in the background (System Settings > General > Login Items) |

## App Structure

The app consists of a single binary compiled with `swiftc`, wrapped in an `.app` bundle. By setting `LSUIElement` in `Info.plist`, it runs as a **menu bar resident app (Agent App) that does not appear in the Dock or in Cmd+Tab**.

### File Structure

```
enja-switcher/
  main.swift                          <- Source code
  AppIcon.icns                        <- App icon (source)
  EnJaSwitcher.app/
    Contents/
      Info.plist                      <- App settings (background operation)
      MacOS/
        enja-switcher                 <- Compiled binary
      Resources/
        AppIcon.icns                  <- App icon
```

### macOS Permissions & System Settings Display

Since this app sends virtual keys and reads keyboard events, macOS security features require the following permissions.

| Location | Reason |
|----------|--------|
| **System Settings > Privacy & Security > Accessibility** | Required to send virtual "Eisuu/Kana" key press events to the system using `CGEvent`. |
| **System Settings > Privacy & Security > Input Monitoring** | Required to read keyboard input state via `CGEventTap` (Command monitoring) and `IOHIDManager` (CapsLock monitoring). |
| **System Settings > General > Login Items > Allow in the Background** | Indicates that auto-start via a LaunchAgent plist is registered. On macOS 13 and later, processes registered via LaunchAgent appear here. |

## Installation

If this is your first time using the app, follow these steps in order.

### Step 1: Check Prerequisites

Verify that Xcode Command Line Tools are installed.

```bash
xcode-select --version
```

If not installed:

```bash
xcode-select --install
```

### Step 2: Clone the Repository

```bash
git clone https://github.com/toshi-kuji/enja-switcher.git
cd enja-switcher
```

### Step 3: Create a Self-Signed Certificate

To avoid having to reconfigure macOS permissions (Accessibility and Input Monitoring) every time the app is updated, sign it with a self-signed certificate. As long as you keep signing with the same certificate, permissions are preserved after rebuilds.

**Steps to create a certificate in Keychain Access:**

1. Open the **Keychain Access** app (search for "Keychain Access" in Spotlight)
2. From the menu bar, select **Keychain Access > Certificate Assistant > Create a Certificate...**
3. Create with the following settings:
   - **Name**: `EnJaSwitcher Dev`
   - **Identity Type**: Self-Signed Root
   - **Certificate Type**: Code Signing
4. Click "Create"

> This step only needs to be done once. The created certificate is saved in the Keychain and can be reused for subsequent builds.

### Step 4: Build, Sign & Deploy

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

### Step 5: First Launch & Grant Permissions

```bash
open /Applications/EnJaSwitcher.app
```

On the first launch, macOS will display a dialog. Open **System Settings > Privacy & Security** and enable `EnJaSwitcher` in both of the following:

- **Accessibility** (required for virtual key dispatch)
- **Input Monitoring** (required for keyboard monitoring)

> **Important**: Always launch the `.app`. Running the binary directly from the terminal will grant permissions to Terminal.app instead, and the app will not work correctly.

### Step 6: Verify Operation

- **Left Command single press** → Switches to English (ABC)
- **Right Command single press** → Switches to Japanese (Hiragana)

Installation is now complete. To enable auto-start at login, see "[Startup Registration (LaunchAgent)](#startup-registration-launchagent)".

## Build & Update (For Developers)

Run the following steps after modifying the code or when updating the app.

### Stop the Running App

```bash
pkill -f enja-switcher
```

### Compile, Sign & Deploy

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
rm -rf /Applications/EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
```

### Launch

```bash
open /Applications/EnJaSwitcher.app
```

> **About Signing and Permissions**
> As long as you sign with the self-signed certificate (`EnJaSwitcher Dev`) created during installation, macOS security permissions (Accessibility and Input Monitoring) **do not need to be reconfigured** after rebuilds. The macOS TCC database identifies apps by their signing identity, so binaries signed with the same certificate are treated as "the same app."
>
> **Note**: If you recreate the certificate or build with a different signature, you will need to reconfigure permissions. Go to System Settings > Privacy & Security and **remove `EnJaSwitcher` with the minus button, then re-add it with the plus button** in both "Accessibility" and "Input Monitoring".

## Startup Registration (LaunchAgent)

To enable auto-start at login, create a LaunchAgent plist file.

**To auto-start for the current user only:**
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

> **Note**: LaunchAgent starts the binary directly via launchd, not through Terminal.app. Permissions are correctly applied to `EnJaSwitcher.app`.

To apply for all users, change the destination to `/Library/LaunchAgents/` and use `sudo` to create the file. However, security permissions (Accessibility and Input Monitoring) must be granted individually for each user.

## How to Stop

Click the "E/J" icon in the menu bar and select **"Quit EnJaSwitcher"** to exit.

If the menu is unresponsive, you can force quit using the following methods.

### Stop via Activity Monitor

1. Open Activity Monitor
2. Type "enja" in the search field
3. Select `enja-switcher` and click the "X" button to quit

### Stop via Terminal

```bash
pkill -f enja-switcher
```

## Uninstallation

To completely remove this app from your system, follow these steps.

### Step 1: Quit the App Process

Exit from the menu bar, or force quit with the following command.
```bash
pkill -f enja-switcher
```

### Step 2: Remove Auto-Start Configuration

```bash
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

### Step 3: Remove the Application

```bash
rm -rf /Applications/EnJaSwitcher.app
```

### Step 4: Clean Up Security Permissions (Manual)

Even after removing the app, old permission entries remain in macOS settings.
1. Open **System Settings > Privacy & Security**.
2. If `EnJaSwitcher` is in the **Accessibility** list, remove it with the **"-" (minus)** button.
3. Similarly, remove it from the **Input Monitoring** list.

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| **Works in the terminal but not in other apps** | Caused by macOS permission blocking. This should not normally occur with a fixed certificate, but if it does, **remove `EnJaSwitcher` with the minus button and re-add it with the plus button** in both "Accessibility" and "Input Monitoring". |
| **Switching does not work** | Try resetting permissions (see above). Verify that you are launching with `open /Applications/EnJaSwitcher.app`. |
| **Does not start after login** | Check the process status with `launchctl list \| grep enja`. Verify that the plist file exists in the correct location. |
| **Switching stops working after a rebuild** | Check the signing information with `codesign -dvv /Applications/EnJaSwitcher.app`. If not signed with the self-signed certificate (`EnJaSwitcher Dev`), remove and re-add in both "Accessibility" and "Input Monitoring" using the minus and plus buttons. |

## Gatekeeper & Security Notes

This app has **not been notarized by Apple** (Apple Developer Program enrollment is required for notarization). As a result, macOS Gatekeeper will block the app when downloaded from the internet. This affects **all Macs**, not just managed corporate devices.

### Method A: Open Anyway (Recommended for downloaded app)

1. Move EnJaSwitcher.app to `/Applications` and double-click it
2. A **"EnJaSwitcher" Not Opened** warning appears → click **Done**
3. Open **System Settings > Privacy & Security** (scroll to the bottom)
4. You'll see **"EnJaSwitcher" was blocked to protect your Mac.** → click **Open Anyway**
5. A confirmation dialog **Open "EnJaSwitcher"?** appears → click **Open Anyway**
6. When permission dialogs appear, grant them (see below)

### Method B: Terminal command

```bash
xattr -cr /Applications/EnJaSwitcher.app
```

Then double-click the app to launch.

### Permissions

On first launch, macOS will prompt you for permissions. Grant both:

- **Accessibility** — required to send virtual Eisuu/Kana key events
- **Input Monitoring** — required to detect Command key and CapsLock presses

You can also enable them manually in **System Settings > Privacy & Security**.

### Build from source

Building locally is the most reliable method — locally built apps are not subject to Gatekeeper checks. Follow the [Installation](#installation) steps above.

> **Note for managed corporate Macs**: If your Mac is managed by MDM (Mobile Device Management), the above bypass methods may be disabled by your organization's security policy. In that case, building from source is the only option.

## Disclaimer

- This app is open-source software developed by an individual, provided as-is with no warranty.
- This app has not been notarized by Apple. See [Gatekeeper & Security Notes](#gatekeeper--security-notes) for details.
- If macOS security policies change significantly in the future, the APIs used by this app (`CGEventTap`, `IOHIDManager`) could be affected.
- Permissions are managed by macOS, and this app does not record or transmit keystroke content.

## Credits

Created by Toshiaki Kujime.

---

# enja-switcher（日本語）

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
- [Gatekeeper・セキュリティについて](#gatekeeperセキュリティについて)
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
| アップデート確認 | GitHub Releases API を定期的に確認し、新バージョンを通知します。個人情報の送信はありません。メニューバーから無効にできます。 |
| 自動起動の管理 | バックグラウンドでの実行を許可（システム設定 > 一般 > ログイン項目） |

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリを含む `.app` バンドルです。`Info.plist` で `LSUIElement` を指定することで、**Dockにも表示されず、Cmd+Tabにも出ないメニューバー常駐アプリ（Agent App）**として動作します。

### ファイル構成

```
enja-switcher/
  main.swift                          <- ソースコード
  AppIcon.icns                        <- アプリアイコン（ソース）
  EnJaSwitcher.app/
    Contents/
      Info.plist                      <- アプリ設定（バックグラウンド動作指定）
      MacOS/
        enja-switcher                 <- コンパイル済みバイナリ
      Resources/
        AppIcon.icns                  <- アプリアイコン
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
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
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
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
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
| **ターミナル内では動くが、他のアプリで動かない** | macOSの権限ブロックが原因。固定署名であれば通常発生しないが、万一の場合は「アクセシビリティ」と「入力監視」のリストから `EnJaSwitcher` を**マイナスボタンで削除し、プラスボタンで再追加**する。 |
| **切り替えが動かない** | 権限のリセット（上記）を試す。`open /Applications/EnJaSwitcher.app` で起動しているか確認。 |
| **ログイン後に起動しない** | `launchctl list \| grep enja` でプロセス状態を確認。plistファイルが正しい場所に存在するか確認。 |
| **ビルド後に切り替えが動かなくなった** | `codesign -dvv /Applications/EnJaSwitcher.app` で署名情報を確認。自己署名証明書（`EnJaSwitcher Dev`）で署名されていない場合は、「アクセシビリティ」と「入力監視」からマイナスで削除して再追加。 |

## Gatekeeper・セキュリティについて

本アプリは**Apple公証（Notarization）を受けていません**（公証にはApple Developer Programへの加入が必要です）。そのため、インターネットからダウンロードした場合、macOS Gatekeeperがアプリをブロックします。これは**会社Macに限らず、すべてのMacで発生します**。

### 方法A: 「このまま開く」で許可（ダウンロード版の推奨手順）

1. EnJaSwitcher.app を `/Applications` に移動してダブルクリック
2. **「"EnJaSwitcher"は開けません」** 警告が表示される → **「完了」** を押す
3. **「システム設定 > プライバシーとセキュリティ」** を開く（一番下までスクロール）
4. **「"EnJaSwitcher"は開発元を確認できないため、使用がブロックされました。」** → **「このまま開く」** を押す
5. 確認ダイアログ **「"EnJaSwitcher"を開きますか？」** → **「このまま開く」** を押す
6. 権限のダイアログが表示されたら許可する（下記参照）

### 方法B: ターミナルコマンド

```bash
xattr -cr /Applications/EnJaSwitcher.app
```

実行後、アプリをダブルクリックして起動してください。

### 権限について

初回起動時に macOS が権限を要求するダイアログを表示します。以下の2つを許可してください:

- **アクセシビリティ** — 仮想的な英数/かなキー送信に必要
- **入力監視** — Command キーや CapsLock の検出に必要

**「システム設定 > プライバシーとセキュリティ」** で手動で有効にすることもできます。

### ソースからビルド

自分のMacでローカルビルドするのが最も確実な方法です。ローカルビルドしたアプリはGatekeeperの検査対象になりません。上記の[インストール手順](#インストール手順)に従ってください。

> **会社Mac（MDM管理下）をお使いの方へ**: MDM（モバイルデバイス管理）で管理されたMacでは、組織のセキュリティポリシーにより上記の回避方法が無効化されている場合があります。その場合は、ソースからのビルドが唯一の選択肢になります。

## 免責事項

- 本アプリは個人が開発したオープンソースソフトウェアであり、動作保証はありません。
- Apple公証（Notarization）を受けていません。詳しくは[Gatekeeper・セキュリティについて](#gatekeeperセキュリティについて)を参照してください。
- macOSのセキュリティポリシーが大幅に変更された場合、本アプリが使用するAPI（`CGEventTap`、`IOHIDManager`）が影響を受ける可能性があります。
- 権限はmacOSが管理しており、本アプリがキー入力の内容を記録・送信することはありません。

## クレジット

作者: Toshiaki Kujime
