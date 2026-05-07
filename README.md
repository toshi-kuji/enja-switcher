# enja-switcher

英語と日本語の入力ソースを瞬時に切り替えるmacOSメニューバー常駐アプリ。

このREADMEは対象読者ごとにセクションに分かれています。あなたに合うものを選んでください。

- [日本語（一般ユーザー向け）](#日本語一般ユーザー向け) — アプリをダウンロードして使いたい方
- [日本語（開発者向け）](#日本語開発者向け) — ソースからビルドしたい方
- [日本語（補足・参考情報）](#日本語補足参考情報) — 仕様や設計判断などを知りたい方
- [English (General Users)](#english-general-users) — Just want to download and use the app
- [English (Developers)](#english-developers) — Want to build from source
- [English (Reference)](#english-reference) — Specs, architecture, design notes

---

# 日本語（一般ユーザー向け）

メニューバーから2つの切り替え方式を選択できるmacOS常駐アプリです。メニューバーの「E/J」アイコンから好みの方式を選択できます。

## 目次

- [できること](#できること)
- [切り替え方式](#切り替え方式)
- [スクロール方向制御](#スクロール方向制御)
- [ダウンロードとインストール](#ダウンロードとインストール)
- [自動起動](#自動起動)
- [自動起動について（重要）](#自動起動について重要)
- [旧バージョンからの移行（任意）](#旧バージョンからの移行任意)
- [停止方法](#停止方法)
- [アンインストール](#アンインストール)
- [トラブルシューティング](#トラブルシューティング)
- [Gatekeeper・セキュリティについて](#gatekeeperセキュリティについて)
- [免責事項](#免責事項)

## できること

- **現在の入力状態を気にせず、目的の言語に直接切り替えられる。** macOS標準の `Ctrl+Space` や `Fn` はトグル式のため「今どちらの言語か」を意識する必要があるが、本アプリではキーと言語が1対1で対応する。
- **Karabiner-Elements等の汎用ツール不要。** `.app` バンドル単体で動作する。
- **macOSの入力ソース切り替えバグを回避。** バックグラウンドから日本語入力に切り替えても、メニューバーの表示と実際の入力状態が食い違わない。

## 切り替え方式

メニューバーの「E/J」アイコンをクリックして、お好みの方式を選択できます。

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

## スクロール方向制御

メニューバーの **Reverse Mouse Scroll** をONにすると、**マウスホイールのみ**の縦スクロール方向が反転します。トラックパッドのスクロールはmacOS標準の「ナチュラルスクロール」設定にそのまま従い、本アプリは介入しません。

これにより、「トラックパッドはナチュラル、マウスは従来方向」のような組み合わせが実現できます（macOS標準の「ナチュラルスクロール」設定はマウスとトラックパッド両方に一律で効くため、この組み合わせは表現できません）。

## ダウンロードとインストール

### ステップ 1: ダウンロード

[GitHub Releases](https://github.com/toshi-kuji/enja-switcher/releases) から最新の `EnJaSwitcher.app.zip` をダウンロードして展開します。

### ステップ 2: アプリを `/Applications` に移動

展開された `EnJaSwitcher.app` を `/Applications` フォルダにドラッグ&ドロップします。

### ステップ 3: Gatekeeper を回避して起動

本アプリは Apple 公証（Notarization）を受けていないため、初回起動時に Gatekeeper の警告が出ます。

1. `/Applications/EnJaSwitcher.app` をダブルクリック
2. **「"EnJaSwitcher"は開けません」** 警告が表示される → **「完了」** を押す
3. **「システム設定 > プライバシーとセキュリティ」** を開く（一番下までスクロール）
4. **「"EnJaSwitcher"は開発元を確認できないため、使用がブロックされました。」** → **「このまま開く」** を押す
5. 確認ダイアログ **「"EnJaSwitcher"を開きますか？」** → **「このまま開く」** を押す

詳細は [Gatekeeper・セキュリティについて](#gatekeeperセキュリティについて) を参照してください。

### ステップ 4: 権限の付与

初回起動時に macOS が権限を要求するダイアログを表示します。以下の2つを許可してください。

- **アクセシビリティ** — 仮想的な英数/かなキー送信に必要
- **入力監視** — Command キーや CapsLock の検出に必要

**システム設定 > プライバシーとセキュリティ** から手動で有効にすることもできます。

### ステップ 5: 動作確認

メニューバーに「E/J」アイコンが表示されることを確認します。

- **左Command 単押し** → 英語（ABC）に切り替わる
- **右Command 単押し** → 日本語（ひらがな）に切り替わる

## 自動起動

**何もする必要はありません**。インストール後、最初にアプリを起動した時点で自動的にログイン時起動が有効になります。

OFF にしたい / 再度 ON にしたい場合は、メニューバーの「E/J」アイコン →「Launch at Login (Background)」のチェックを切り替えてください。

## 自動起動について（重要）

上記の自動起動設定を行うと、macOS の動作として以下のことが起きます。**いずれも正常な動作で、安心してそのまま使ってOK**です。

### 1. 「バックグラウンドでの実行を許可」に黒いアイコンが表示される

**システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** のリストに `enja-switcher` という名前で **黒い四角に "exec" と書かれたアイコン** が表示されます。

「署名されていない不審なアプリ？」と感じるかもしれませんが、これは macOS の表示仕様です。

- 自動起動の仕組み（LaunchAgent）は `.app` バンドルではなく**バンドル内の実行ファイル（バイナリ）を直接起動する**ため、macOS は `.app` のアイコン情報を読まずに「裸の実行ファイル」のデフォルトアイコンを表示する
- アプリ自体は自己署名証明書で正しく署名されており、動作上の問題はない
- このトグルは **ON のまま** にしてください（OFF にすると自動起動しなくなる）

初回登録時には `"EnJaSwitcher.app added items that can run in the background"` という通知が1回だけ表示されますが、何もしなくても自動起動は有効になります。

### 2. 「ログイン項目（Open at Login）」への手動追加は不要

**システム設定 > 一般 > ログイン項目 > Open at Login** に EnJaSwitcher を追加する必要は **ありません**。上記の自動起動設定（LaunchAgent）が同じ役割を果たしています。

もし両方に登録されている場合は、`Open at Login` 側を選択してマイナスボタンで削除してください（バックグラウンド側の方を残す）。

## 旧バージョンからの移行（任意）

v1.3.0 以前で、旧 README の手順に従って `/Library/LaunchAgents/` にシステム全体の LaunchAgent を `sudo` で手動セットアップしていた方向けの案内です。

**現状のままでも問題なく動作します**。レガシーの LaunchAgent が引き続きログイン時の自動起動を担当しているので、何もしなくて構いません。

ただし、新方式（v1.3.0 のアプリ自動セットアップ）に移行すると以下のメリットがあります：

- **メニューから ON/OFF 切り替え可能** — ターミナル不要
- **ユーザー単位での管理** — マルチユーザー Mac で各ユーザーが個別に設定可能。旧方式は Mac 全ユーザーに適用される
- **アンインストール時に sudo 不要** — 新方式は `~/Library/LaunchAgents/` に配置されるため、自分の領域だけで完結
- **ログイン時の起動が早い** — 新方式の plist には `ProcessType: Interactive` が含まれるため、launchd が他のバックグラウンドタスクより優先的に起動する。旧方式は ProcessType 未指定で軽量タスク扱い（throttling 対象）になり、ログイン直後ではなく数十秒〜1 分ほど遅れて起動することがある

### 移行手順

1. ターミナルで以下を実行（1 行）。アプリの終了とレガシー削除がまとめて行われます：

   ```bash
   pkill -f enja-switcher 2>/dev/null; sudo launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null; sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
   ```

2. EnJaSwitcher を再度開く（`open /Applications/EnJaSwitcher.app`）

新方式の自動セットアップが走り、メニューバーの「Launch at Login (Background)」が ON 状態になります。

## 停止方法

メニューバーの「E/J」アイコンをクリックし、**「Quit EnJaSwitcher」** を選択して終了します。

メニューが反応しない場合は、**アクティビティモニタ** を開いて検索欄に「enja」と入力し、`enja-switcher` を選択して「×」ボタンで終了してください。

## アンインストール

ターミナルで以下を順に実行してください。

```bash
# 1. 自動起動設定の削除
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.enja-switcher.plist

# 2. プロセスの終了
pkill -f enja-switcher

# 3. アプリ本体の削除
rm -rf /Applications/EnJaSwitcher.app
```

その後、**システム設定 > プライバシーとセキュリティ** を開き、「アクセシビリティ」「入力監視」のリストから `EnJaSwitcher` をマイナスボタンで削除してください（残しておいても無害ですが、リストから完全に消したい場合のみ）。

## トラブルシューティング

| 症状 | 対処法 |
|------|--------|
| **切り替えが動かない** | 「アクセシビリティ」と「入力監視」の両方で `EnJaSwitcher` が ON になっているか確認。ON なのに動かない場合は、**マイナスボタンで削除してプラスボタンで再追加**する。 |
| **ログイン後に自動起動しない** | メニューバーの「Launch at Login (Background)」が ON になっているか確認。「バックグラウンドでの実行を許可」のトグルも ON か確認。レガシー設定（旧 README で `/Library/LaunchAgents/` に配置した方）の場合、ログイン直後ではなく **約 1 分後に起動** することがある（[旧バージョンからの移行](#旧バージョンからの移行任意) で解消）。 |
| **メニューバーにアイコンが出ない** | `pkill -f enja-switcher` で一旦終了してから `open /Applications/EnJaSwitcher.app` で再起動。 |
| **アップデート後に切り替えが動かなくなった** | 新バージョンをダウンロードして上書きインストールした後、「アクセシビリティ」と「入力監視」から削除して再追加。 |

## Gatekeeper・セキュリティについて

本アプリは **Apple 公証（Notarization）を受けていません**（公証には Apple Developer Program への加入が必要です）。そのため、インターネットからダウンロードした場合、macOS Gatekeeper がアプリをブロックします。これは **会社 Mac に限らず、すべての Mac で発生します**。**アップデート時も同様**で、新しいバージョンをダウンロードするたびに同じ手順が必要です。

### 「このまま開く」で許可（推奨）

[ダウンロードとインストール](#ダウンロードとインストール) のステップ 3 に記載の手順で許可します。

### ターミナルコマンドで一括解除

```bash
xattr -cr /Applications/EnJaSwitcher.app
```

実行後、アプリをダブルクリックして起動してください。

> **会社 Mac（MDM 管理下）をお使いの方へ**: MDM（モバイルデバイス管理）で管理された Mac では、組織のセキュリティポリシーにより上記の回避方法が無効化されている場合があります。その場合は、開発者向けセクションを参照してソースからビルドしてください。

## 免責事項

- 本アプリは個人が開発したオープンソースソフトウェアであり、動作保証はありません。
- Apple 公証（Notarization）を受けていません。詳しくは [Gatekeeper・セキュリティについて](#gatekeeperセキュリティについて) を参照してください。
- macOS のセキュリティポリシーが大幅に変更された場合、本アプリが使用する API が影響を受ける可能性があります。
- 権限は macOS が管理しており、本アプリがキー入力の内容を記録・送信することはありません。

作者: Toshiaki Kujime

---

# 日本語（開発者向け）

ソースからビルドしたい方向けのセクションです。**ビルド後のインストール・権限付与・自動起動・停止・アンインストールの手順は一般ユーザー向けセクションと同じ**なので、ビルドが終わったら [日本語（一般ユーザー向け）](#日本語一般ユーザー向け) を参照してください。

## 目次

- [開発環境の前提](#開発環境の前提)
- [ビルド手順（初回）](#ビルド手順初回)
- [更新ワークフロー（再ビルド時）](#更新ワークフロー再ビルド時)

## 開発環境の前提

Xcode Command Line Tools がインストールされていることを確認します。

```bash
xcode-select --version
```

インストールされていない場合：

```bash
xcode-select --install
```

## ビルド手順（初回）

### ステップ 1: リポジトリのクローン

```bash
git clone https://github.com/toshi-kuji/enja-switcher.git
cd enja-switcher
```

### ステップ 2: 自己署名証明書の作成

アプリの更新時に macOS の権限（アクセシビリティ・入力監視）を再設定する手間をなくすため、自己署名証明書で署名します。**同じ証明書で署名し続ける限り、再ビルド後も権限は維持されます**。

**Keychain Access で証明書を作成する手順：**

1. **Keychain Access** アプリを開く（Spotlight で「Keychain Access」と検索）
2. メニューバーから **Keychain Access > 証明書アシスタント > 証明書を作成...** を選択
3. 以下の設定で作成:
   - **名前**: `EnJaSwitcher Dev`
   - **固有名のタイプ**: 自己署名ルート
   - **証明書のタイプ**: コード署名
4. 「作成」をクリック

> この手順は初回の 1 回だけ実行すれば十分です。作成した証明書は Keychain に保存され、以降のビルドで繰り返し使用できます。

### ステップ 3: ビルド・署名・配置

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
open /Applications/EnJaSwitcher.app
```

### ステップ 4: ここからは一般ユーザー向け手順と同じ

- 権限の付与 → [ステップ 4: 権限の付与](#ステップ-4-権限の付与)
- 自動起動の設定 → [自動起動の設定](#自動起動の設定)

> **重要**: 必ず `.app` として起動してください（`open /Applications/EnJaSwitcher.app`）。ターミナルからバイナリを直接実行すると、権限が Terminal.app に付与されてしまい正しく動作しません。

## 更新ワークフロー（再ビルド時）

コードを変更した後や、アプリを更新する際は以下の手順を実行します。

```bash
pkill -f enja-switcher
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
rm -rf /Applications/EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
open /Applications/EnJaSwitcher.app
```

> **署名と権限について**
> インストール時に作成した自己署名証明書（`EnJaSwitcher Dev`）で署名している限り、再ビルド後も macOS のセキュリティ権限（アクセシビリティ・入力監視）は **再設定不要** です。macOS の TCC データベースは署名の identity でアプリを識別するため、同じ証明書で署名されたバイナリは「同じアプリ」として扱われます。
>
> **注意**: 証明書を作り直した場合や、異なる署名でビルドした場合は、権限の再設定が必要です。システム設定 > プライバシーとセキュリティ から「アクセシビリティ」と「入力監視」の両方で、`EnJaSwitcher` を **マイナスボタンで削除してからプラスボタンで再追加** してください。

---

# 日本語（補足・参考情報）

仕様、内部構造、設計判断についての参考情報です。一般利用や開発に必須ではありませんが、興味のある方向け。

## 目次

- [仕様](#仕様)
- [アプリの構造](#アプリの構造)
- [必要権限と System Settings の表示](#必要権限と-system-settings-の表示)
- [スクロール方向制御の仕組み](#スクロール方向制御の仕組み)
- [LaunchAgent 方式を選んだ理由](#launchagent-方式を選んだ理由)
- [開発時のトラブルシューティング](#開発時のトラブルシューティング)

## 仕様

| 項目 | 内容 |
|------|------|
| 対象 OS | macOS 13 以降（Apple Silicon / Intel） |
| ランタイム依存 | なし（Swift 標準ライブラリは OS に内蔵） |
| ビルドツール | `swiftc`（Xcode Command Line Tools） |
| 配布形式 | `.app` バンドル（Dock に表示されないバックグラウンドアプリ） |
| 判定方式 | `CGEventTap`（Command 監視）および `IOHIDManager`（CapsLock 監視） |
| 設定保存 | `UserDefaults` を用いて選択した切り替え方式を永続化 |
| 切り替え条件 | Command キー単押し、または CapsLock の単押し / 二度押し |
| 他キー併用無視 | Command+C などコンビネーション操作では切り替えが発動しない |
| 入力ソース切替 | 仮想キーコード送信（左 Cmd: `102` 英数, 右 Cmd: `104` かな） |
| 必要権限 | **アクセシビリティ** および **入力監視** |
| アップデート確認 | GitHub Releases API を定期的に確認し、新バージョンを通知。個人情報の送信なし。メニューバーから無効化可。 |
| 自動起動の管理 | バックグラウンドでの実行を許可（システム設定 > 一般 > ログイン項目） |

## アプリの構造

本アプリの実体は `swiftc` でコンパイルした単一バイナリを含む `.app` バンドルです。`Info.plist` で `LSUIElement` を指定することで、**Dock にも表示されず、Cmd+Tab にも出ないメニューバー常駐アプリ（Agent App）** として動作します。

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

## 必要権限と System Settings の表示

| 表示場所 | 理由 |
|----------|------|
| **システム設定 > プライバシーとセキュリティ > アクセシビリティ** | `CGEvent` を用いて仮想的な「英数 / かな」キー押下イベントをシステムに送信（エミュレート）するために必要。 |
| **システム設定 > プライバシーとセキュリティ > 入力監視** | `CGEventTap`（Command 監視）および `IOHIDManager`（CapsLock 監視）でキーボードの入力状態を読み取るために必要。 |
| **システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可** | LaunchAgent plist による自動起動が登録されていることを示す。macOS 13 以降、LaunchAgent で登録されたプロセスはここに表示される。 |

## スクロール方向制御の仕組み

- マウス / トラックパッドの判別は CGEvent の `scrollPhase` / `momentumPhase` フィールドで行う。トラックパッドイベントにはフェーズ情報が付与され、マウスホイールイベントには付かない。
- トラックパッドイベントは素通し。マウスイベントでは、元イベントを破棄し Y 軸のラインデルタを反転した新規スクロールイベントを生成して差し替える（macOS が元イベントの内部バッファを使い回すため、フィールドの直接変更はアプリに反映されない）。
- スクロールイベント tap は起動時に 1 回だけ作成し、ON/OFF は `CGEvent.tapEnable` で切り替える。tap の作成・破棄を繰り返すと権限キャッシュが破損するリスクがあるため、この方式を採用している。
- 横スクロール（Axis2）は保持される。追加の権限は不要。

## LaunchAgent 方式を選んだ理由

本アプリは自動起動の仕組みとして、macOS 13 以降の `SMAppService`（Login Item 登録 API）ではなく、従来の **LaunchAgent plist** 方式を採用しています。v1.3.0 以降はアプリが `~/Library/LaunchAgents/` に plist を自動生成・登録します。

| 観点 | LaunchAgent 方式の利点 |
|---|---|
| 起動優先度の制御 | plist に `ProcessType: Interactive` を指定することで launchd の起動優先度を上げ、ログイン直後の遅延を最小化できる |
| 軽量性 | `.app` バンドル + plist のみで動作し、追加のフレームワーク依存がない |
| 明示的な制御 | `launchctl` コマンドで開発時に start / stop / 状態確認ができる |
| 透過性 | plist の中身が見える形でディスクに置かれるため、何が登録されているかユーザーが直接確認できる |

**Login Item 方式（`SMAppService`）と比較したトレードオフ：**

- Login Item 方式は「Open at Login」セクションにアプリアイコンが正しく表示されるため、UX 上は綺麗
- LaunchAgent 方式は「バックグラウンドでの実行を許可」セクションに `enja-switcher` という裸のバイナリ名と "exec" デフォルトアイコンで表示されるため、ユーザーから見ると不安に感じる可能性がある（→ 一般ユーザー向けセクションで説明することで対処）
- 上記の利点を優先して LaunchAgent 方式を採用

## 開発時のトラブルシューティング

| 症状 | 対処法 |
|------|--------|
| **ターミナル内では動くが、他のアプリで動かない** | macOS の権限ブロックが原因。固定署名であれば通常発生しないが、万一の場合は「アクセシビリティ」と「入力監視」のリストから `EnJaSwitcher` を **マイナスボタンで削除し、プラスボタンで再追加** する。 |
| **切り替えが動かない** | 権限のリセット（上記）を試す。`open /Applications/EnJaSwitcher.app` で起動しているか確認。 |
| **ログイン後に起動しない** | `launchctl list \| grep enja` でプロセス状態を確認。plist ファイルが `~/Library/LaunchAgents/com.local.enja-switcher.plist` に存在するか確認。 |
| **ビルド後に切り替えが動かなくなった** | `codesign -dvv /Applications/EnJaSwitcher.app` で署名情報を確認。自己署名証明書（`EnJaSwitcher Dev`）で署名されていない場合は、「アクセシビリティ」と「入力監視」からマイナスで削除して再追加。 |
| **イベントタップが動作しない** | `passRetained` を `passUnretained` に変更していないか確認。また、定数（`leftCommandBit` 等）をクロージャ外のグローバルスコープに移動していないか確認。 |

---

# English (General Users)

A macOS menu bar resident app (input source switcher) that lets you choose between two switching methods from the menu bar. Select your preferred method from the "E/J" icon in the menu bar.

## Table of Contents

- [What It Does](#what-it-does)
- [Switching Methods](#switching-methods)
- [Scroll Direction Control](#scroll-direction-control)
- [Download & Install](#download--install)
- [Auto-Start at Login](#auto-start-at-login)
- [About Auto-Start (Important)](#about-auto-start-important)
- [Migrating from Older Versions (Optional)](#migrating-from-older-versions-optional)
- [How to Stop](#how-to-stop)
- [Uninstallation](#uninstallation)
- [Troubleshooting](#troubleshooting)
- [Gatekeeper & Security Notes](#gatekeeper--security-notes)
- [Disclaimer](#disclaimer)

## What It Does

- **Switch directly to the desired language without worrying about the current input state.** macOS's standard `Ctrl+Space` or `Fn` are toggle-based, requiring you to be aware of the current language. With this tool, each key maps directly to one language.
- **No general-purpose tools like Karabiner-Elements required.** Runs as a standalone `.app` bundle.
- **Works around macOS's input source switching bug.** Even when switching to Japanese input from the background, the menu bar display and the actual input state stay in sync.

## Switching Methods

Click the "E/J" icon in the menu bar to choose your preferred method.

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

## Scroll Direction Control

Toggle **Reverse Mouse Scroll** from the menu bar to reverse the vertical scroll direction of **mouse wheel events only**. Trackpad scrolling follows macOS's own "Natural Scrolling" setting and is not touched.

This lets you set "natural scrolling on trackpad, traditional on mouse" (or any other combination of the two), which macOS's built-in settings cannot express — its "Natural Scrolling" toggle applies to both devices at once.

## Download & Install

### Step 1: Download

Download the latest `EnJaSwitcher.app.zip` from [GitHub Releases](https://github.com/toshi-kuji/enja-switcher/releases) and unzip it.

### Step 2: Move the App to `/Applications`

Drag the unzipped `EnJaSwitcher.app` into the `/Applications` folder.

### Step 3: Bypass Gatekeeper to Launch

This app has not been notarized by Apple, so Gatekeeper will warn on first launch.

1. Double-click `/Applications/EnJaSwitcher.app`
2. A **"EnJaSwitcher" Not Opened** warning appears → click **Done**
3. Open **System Settings > Privacy & Security** (scroll to the bottom)
4. You'll see **"EnJaSwitcher" was blocked to protect your Mac.** → click **Open Anyway**
5. A confirmation dialog **Open "EnJaSwitcher"?** appears → click **Open Anyway**

See [Gatekeeper & Security Notes](#gatekeeper--security-notes) for details.

### Step 4: Grant Permissions

On first launch, macOS will display permission dialogs. Grant both:

- **Accessibility** — required to send virtual Eisuu/Kana key events
- **Input Monitoring** — required to detect Command key and CapsLock presses

You can also enable them manually in **System Settings > Privacy & Security**.

### Step 5: Verify Operation

Confirm that the "E/J" icon appears in the menu bar.

- **Left Command single press** → Switches to English (ABC)
- **Right Command single press** → Switches to Japanese (Hiragana)

## Auto-Start at Login

**Nothing to do** — auto-start at login is enabled automatically the first time you launch the app after installation.

To turn it off (or back on), click the "E/J" icon in the menu bar and toggle **"Launch at Login (Background)"**.

## About Auto-Start (Important)

Once you enable auto-start above, you'll notice the following macOS behaviors. **Both are normal — feel free to leave everything as-is.**

### 1. A Black Icon Appears Under "Allow in the Background"

In **System Settings > General > Login Items > Allow in the Background**, you'll see an entry named `enja-switcher` with **a black square icon labeled "exec"**.

You might wonder, "Is this an unsigned, suspicious app?" — but this is just how macOS displays it.

- The auto-start mechanism (LaunchAgent) launches the **executable file directly** (the binary inside the bundle), not the `.app` bundle itself. So macOS doesn't read the `.app`'s icon information and shows the default "naked executable" icon instead.
- The app itself **is** properly signed with a self-signed certificate; there is no functional issue.
- **Leave this toggle ON** (turning it off will disable auto-start).

On first registration, macOS shows a one-time notification `"EnJaSwitcher.app added items that can run in the background"`. You don't need to do anything — auto-start is already enabled.

### 2. No Need to Add to "Open at Login" Manually

You do **not** need to add EnJaSwitcher to **System Settings > General > Login Items > Open at Login**. The auto-start setup above (LaunchAgent) already handles this.

If you find it registered in both places, you can remove it from `Open at Login` (keep the entry under "Allow in the Background").

## Migrating from Older Versions (Optional)

This section is for users who previously followed the older README and manually set up a system-wide LaunchAgent at `/Library/LaunchAgents/` with `sudo`.

**You can keep using the legacy setup with no issue** — the legacy LaunchAgent continues to handle auto-start at login, and you don't have to do anything.

That said, migrating to the new in-app auto-setup (introduced in v1.3.0) offers the following benefits:

- **Toggle ON/OFF from the menu** — no Terminal required
- **Per-user management** — on multi-user Macs, each user controls their own setup. The legacy method applies to every user of the Mac
- **No sudo required for uninstallation** — the new method places the plist under `~/Library/LaunchAgents/`, so removing it stays in your own home directory
- **Faster launch at login** — the new plist includes `ProcessType: Interactive`, so launchd starts it with higher priority than other background tasks. The legacy plist has no `ProcessType`, which causes launchd to apply lightweight (throttled) scheduling — login-time launches can be delayed by several tens of seconds up to about a minute

### Migration Steps

1. Run the following in Terminal (one line). This quits EnJaSwitcher and removes the legacy install in one go:

   ```bash
   pkill -f enja-switcher 2>/dev/null; sudo launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null; sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
   ```

2. Reopen EnJaSwitcher (`open /Applications/EnJaSwitcher.app`)

The new auto-setup runs and the menu's "Launch at Login (Background)" toggle becomes ON.

## How to Stop

Click the "E/J" icon in the menu bar and select **"Quit EnJaSwitcher"** to exit.

If the menu is unresponsive, open **Activity Monitor**, type "enja" in the search field, select `enja-switcher`, and click the "X" button to quit.

## Uninstallation

Run the following commands in Terminal in order.

```bash
# 1. Remove auto-start configuration
launchctl unload ~/Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.enja-switcher.plist

# 2. Quit the process
pkill -f enja-switcher

# 3. Remove the app
rm -rf /Applications/EnJaSwitcher.app
```

Then open **System Settings > Privacy & Security** and remove `EnJaSwitcher` with the minus button from "Accessibility" and "Input Monitoring" (harmless if left, but remove if you want a clean list).

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| **Switching does not work** | Verify `EnJaSwitcher` is ON in both "Accessibility" and "Input Monitoring". If still not working, **remove with the minus button and re-add with the plus button**. |
| **Does not auto-start at login** | Verify "Launch at Login (Background)" is checked in the menu bar, and the "Allow in the Background" toggle is ON in System Settings. If you're using the legacy setup (the one in older READMEs that placed the plist at `/Library/LaunchAgents/`), launchd may delay the launch by **about 1 minute** after login — see [Migrating from Older Versions](#migrating-from-older-versions-optional) to fix this. |
| **No icon in the menu bar** | Run `pkill -f enja-switcher` to terminate, then `open /Applications/EnJaSwitcher.app` to restart. |
| **Switching stops working after an update** | After installing the new version, remove and re-add `EnJaSwitcher` from both "Accessibility" and "Input Monitoring". |

## Gatekeeper & Security Notes

This app has **not been notarized by Apple** (Apple Developer Program enrollment is required for notarization). As a result, macOS Gatekeeper will block the app when downloaded from the internet. This affects **all Macs**, not just managed corporate devices. **This applies to updates as well** — each time you download a new version, the same bypass steps are required.

### Open Anyway (Recommended)

Follow the steps in Step 3 of [Download & Install](#download--install).

### Bypass via Terminal Command

```bash
xattr -cr /Applications/EnJaSwitcher.app
```

Then double-click the app to launch.

> **Note for managed corporate Macs**: If your Mac is managed by MDM (Mobile Device Management), the above bypass methods may be disabled by your organization's security policy. In that case, refer to the developer section and build from source.

## Disclaimer

- This app is open-source software developed by an individual, provided as-is with no warranty.
- This app has not been notarized by Apple. See [Gatekeeper & Security Notes](#gatekeeper--security-notes) for details.
- If macOS security policies change significantly in the future, the APIs used by this app could be affected.
- Permissions are managed by macOS, and this app does not record or transmit keystroke content.

Created by Toshiaki Kujime.

---

# English (Developers)

For those who want to build from source. **Installation, permissions, auto-start, stopping, and uninstallation are identical to the general user flow** — once you've built the app, follow [English (General Users)](#english-general-users).

## Table of Contents

- [Development Prerequisites](#development-prerequisites)
- [Build Steps (First Time)](#build-steps-first-time)
- [Update Workflow (Rebuild)](#update-workflow-rebuild)

## Development Prerequisites

Verify that Xcode Command Line Tools are installed.

```bash
xcode-select --version
```

If not installed:

```bash
xcode-select --install
```

## Build Steps (First Time)

### Step 1: Clone the Repository

```bash
git clone https://github.com/toshi-kuji/enja-switcher.git
cd enja-switcher
```

### Step 2: Create a Self-Signed Certificate

To avoid having to reconfigure macOS permissions (Accessibility and Input Monitoring) every time the app is updated, sign it with a self-signed certificate. **As long as you keep signing with the same certificate, permissions are preserved after rebuilds.**

**Steps to create a certificate in Keychain Access:**

1. Open the **Keychain Access** app (search for "Keychain Access" in Spotlight)
2. From the menu bar, select **Keychain Access > Certificate Assistant > Create a Certificate...**
3. Create with the following settings:
   - **Name**: `EnJaSwitcher Dev`
   - **Identity Type**: Self-Signed Root
   - **Certificate Type**: Code Signing
4. Click "Create"

> This step only needs to be done once. The created certificate is saved in the Keychain and can be reused for subsequent builds.

### Step 3: Build, Sign & Deploy

```bash
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
open /Applications/EnJaSwitcher.app
```

### Step 4: From here, follow the general user flow

- Grant permissions → [Step 4: Grant Permissions](#step-4-grant-permissions)
- Enable auto-start → [Enable Auto-Start at Login](#enable-auto-start-at-login)

> **Important**: Always launch the `.app` (`open /Applications/EnJaSwitcher.app`). Running the binary directly from the terminal will grant permissions to Terminal.app instead, and the app will not work correctly.

## Update Workflow (Rebuild)

Run the following steps after modifying the code or when updating the app.

```bash
pkill -f enja-switcher
swiftc -O -o enja-switcher main.swift -framework Carbon -framework Cocoa -framework IOKit
mkdir -p EnJaSwitcher.app/Contents/{MacOS,Resources}
cp Info.plist EnJaSwitcher.app/Contents/
cp AppIcon.icns EnJaSwitcher.app/Contents/Resources/
cp enja-switcher EnJaSwitcher.app/Contents/MacOS/
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
rm -rf /Applications/EnJaSwitcher.app
cp -r EnJaSwitcher.app /Applications/
open /Applications/EnJaSwitcher.app
```

> **About Signing and Permissions**
> As long as you sign with the self-signed certificate (`EnJaSwitcher Dev`) created during installation, macOS security permissions (Accessibility and Input Monitoring) **do not need to be reconfigured** after rebuilds. The macOS TCC database identifies apps by their signing identity, so binaries signed with the same certificate are treated as "the same app."
>
> **Note**: If you recreate the certificate or build with a different signature, you will need to reconfigure permissions. Go to System Settings > Privacy & Security and **remove `EnJaSwitcher` with the minus button, then re-add it with the plus button** in both "Accessibility" and "Input Monitoring".

---

# English (Reference)

Specifications, internal architecture, and design decisions. Not required for using or building the app — for those who want to know.

## Table of Contents

- [Specifications](#specifications)
- [App Structure](#app-structure)
- [Required Permissions & System Settings Display](#required-permissions--system-settings-display)
- [Scroll Direction Control: How It Works](#scroll-direction-control-how-it-works)
- [Why LaunchAgent Was Chosen](#why-launchagent-was-chosen)
- [Troubleshooting (Development)](#troubleshooting-development)

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
| Update check | Periodically checks GitHub Releases API. No personal data is sent. Can be disabled from the menu bar. |
| Auto-start management | Allow in the Background (System Settings > General > Login Items) |

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

## Required Permissions & System Settings Display

| Location | Reason |
|----------|--------|
| **System Settings > Privacy & Security > Accessibility** | Required to send virtual "Eisuu/Kana" key press events to the system using `CGEvent`. |
| **System Settings > Privacy & Security > Input Monitoring** | Required to read keyboard input state via `CGEventTap` (Command monitoring) and `IOHIDManager` (CapsLock monitoring). |
| **System Settings > General > Login Items > Allow in the Background** | Indicates that auto-start via a LaunchAgent plist is registered. On macOS 13 and later, processes registered via LaunchAgent appear here. |

## Scroll Direction Control: How It Works

- Mouse vs. trackpad is detected via the CGEvent `scrollPhase` / `momentumPhase` fields. Trackpad events carry phase information; mouse wheel events do not.
- Trackpad events pass through untouched. For mouse events, the original event is replaced with a new scroll event whose Y-axis line delta is negated. macOS ignores in-place field modifications on the original event, so a fresh event must be created.
- The scroll event tap is created once at launch and toggled via `CGEvent.tapEnable`. It is not destroyed and re-created, to avoid corrupting the macOS permission cache.
- Horizontal scrolling (Axis2) is preserved. No additional permissions required.

## Why LaunchAgent Was Chosen

This app uses the traditional **LaunchAgent plist** approach for auto-start, rather than the macOS 13+ `SMAppService` (Login Item registration API). From v1.3.0 onward, the app automatically generates and registers the plist under `~/Library/LaunchAgents/`.

| Aspect | Advantage of the LaunchAgent approach |
|---|---|
| Launch priority control | Setting `ProcessType: Interactive` in the plist lets launchd start the app with higher priority, minimizing the post-login delay |
| Lightweight | Works with just the `.app` bundle and a plist; no additional framework dependencies |
| Explicit control | `launchctl` lets you start / stop / inspect status during development |
| Transparency | The plist sits on disk in plain text, so users can directly inspect what is registered |

**Tradeoffs vs. the Login Item approach (`SMAppService`):**

- The Login Item approach displays the app icon properly in the "Open at Login" section, which is cleaner UX
- The LaunchAgent approach displays as `enja-switcher` (the bare binary name) with the default "exec" icon under "Allow in the Background", which may look unsettling to users (→ addressed by an explanatory section in the General Users README)
- The benefits above outweigh the UI cost

## Troubleshooting (Development)

| Symptom | Solution |
|---------|----------|
| **Works in the terminal but not in other apps** | Caused by macOS permission blocking. This should not normally occur with a fixed certificate, but if it does, **remove `EnJaSwitcher` with the minus button and re-add it with the plus button** in both "Accessibility" and "Input Monitoring". |
| **Switching does not work** | Try resetting permissions (see above). Verify that you are launching with `open /Applications/EnJaSwitcher.app`. |
| **Does not start after login** | Check the process status with `launchctl list \| grep enja`. Verify that the plist file exists at `~/Library/LaunchAgents/com.local.enja-switcher.plist`. |
| **Switching stops working after a rebuild** | Check the signing information with `codesign -dvv /Applications/EnJaSwitcher.app`. If not signed with the self-signed certificate (`EnJaSwitcher Dev`), remove and re-add in both "Accessibility" and "Input Monitoring" using the minus and plus buttons. |
| **Event tap stops working** | Verify you have not changed `passRetained` to `passUnretained`. Also verify constants (e.g., `leftCommandBit`) have not been moved out of the closure into global scope. |
