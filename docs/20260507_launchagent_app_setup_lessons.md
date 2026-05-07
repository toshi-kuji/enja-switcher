# macOS の LaunchAgent をアプリ内で自動管理する時の落とし穴と設計判断

**日付**: 2026-05-07
**きっかけ**: EnJaSwitcher v1.3.0 で「アプリが自分で LaunchAgent を管理し、メニューから ON/OFF できる」機能を実装した過程で踏んだ罠と、そこから得た学びの記録。

このドキュメントは、macOS のメニューバー常駐アプリ（Agent App）を作る人や、LaunchAgent 周りで詰まった人が、同じ落とし穴にハマらないようにするためのまとめです。

---

## 0. 全体像

メニューバー常駐型アプリで「ログイン時に自動起動するか」をユーザーが切り替えられる機能を作る場合、選択肢は大きく 2 つ：

| 方式 | API | 配置先 |
|---|---|---|
| **LaunchAgent**（伝統） | `launchctl` + plist | `~/Library/LaunchAgents/` または `/Library/LaunchAgents/` |
| **Login Item**（モダン） | `SMAppService.mainApp` | OS の管理する内部 DB |

EnJaSwitcher は LaunchAgent 方式を採用しているが、**LaunchAgent は伝統的すぎて挙動が複雑**。今回はそこで色々踏んだ。

---

## 1. plist に `KeepAlive: true` を入れてはいけない（メニューバーアプリの場合）

### 何が起きるか

`KeepAlive: true` は launchd に「ジョブを常に生かす」と指示する。プロセスが終了すると（正常 / クラッシュにかかわらず）launchd が自動で再起動する。

メニューバーアプリでこれを入れると、ユーザーがメニューから「Quit」を選んでも：

```
1. アプリが NSApp.terminate(nil) で終了
2. launchd が「ジョブが死んだ」と検知
3. 即座に launchd が再起動
4. ユーザー：「何で Quit したのにまた起動してる？」
```

### 教訓

- 自動再起動が欲しいデーモン（バックグラウンドで稼働し続けるサーバー的なもの）には適切
- メニューバーアプリは「ユーザーが明示的に Quit したい」ことがあるので、`KeepAlive` は入れない（または `false`）
- クラッシュ時の自動回復が欲しいなら `SuccessfulExit: false` を辞書形式で指定する手もあるが、メニューバーアプリではあまり必要ない

---

## 2. `launchctl unload -w` は SIGTERM で実行中アプリを kill する

### 何が起きるか

`launchctl unload -w /path/to/plist` は launchd のジョブ登録を解除する。このとき、登録されたジョブの実行中プロセスに **SIGTERM が送られて即終了する**。

メニューから「自動起動 OFF」のトグルでこれを呼ぶと、自分自身が死ぬ：

```swift
@objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    // ...
    LaunchAgent.uninstall()  // ← この中で launchctl unload -w を呼ぶと
                              //    自分が SIGTERM で死ぬ
}
```

ユーザーから見ると「OFF にしたらアプリが消えた」という意外な挙動。

### 教訓

「自動起動 OFF」の意味は「次回ログインから auto-start しない」であって「今走ってるアプリを終了する」ではない。なので：

- `uninstall()` では **plist ファイルを削除するだけ** にする（`launchctl unload` は呼ばない）
- in-memory のジョブ登録は launchd に残るが、`KeepAlive` がなければ何もしない（プロセスが死んでも respawn しない）
- 次回ログイン時にはファイルが無いので launchd は新規ロードしない → auto-start も走らない

実装：

```swift
static func uninstall() {
    try? FileManager.default.removeItem(atPath: userPlistPath)
    // ↑ これだけ。launchctl unload は呼ばない
}
```

---

## 3. `launchctl load -w` は新プロセスを spawn する（重複稼働）

### 何が起きるか

`launchctl load -w /path/to/plist` でロードすると、plist に `RunAtLoad: true` が指定されていれば launchd が **即座にバイナリを起動する**。

問題：すでにアプリが `open` で起動して走っているのに、その状態で `launchctl load` を呼ぶと：

```
プロセス A: open で起動中
launchctl load → 新プロセス B が launchd により起動
結果：A と B が両方走る → メニューバーアイコンも 2 つ
```

これが「ON にトグルしたら何故か EnJaSwitcher が 2 つ走り出した」現象の正体。

### 教訓

`launchctl load -w` は避けて通れない（macOS 13+ では Background Item Management に登録するために必要：後述）。なので **重複検知をアプリ起動時に入れて、後発組を `exit(0)` させる**。

```swift
// main の最初で
let myPID = ProcessInfo.processInfo.processIdentifier
let dups = NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.local.enja-switcher")
    .filter { $0.processIdentifier != pid_t(myPID) }
if !dups.isEmpty {
    // 自分が後から起動した重複プロセス → 退場
    exit(0)
}
```

これで `open`-spawned の A が継続、launchctl-spawned の B が即 exit する形に収まる。

---

## 4. macOS 13+ では plist をディスクに置くだけでは auto-start しない

### 試したこと（失敗パターン）

「`launchctl load -w` で新プロセスがスポーンするのが嫌だから、plist ファイルを書くだけにする」と最初考えた：

```swift
static func install() {
    try? plistContents().write(toFile: userPlistPath, ...)
    // launchctl は呼ばない
}
```

`~/Library/LaunchAgents/` にファイルが置かれるので、launchd が次回ログイン時に拾ってくれるはず…と思った。

### 結果

**次回ログイン時に auto-start しない**。

### 原因

macOS 13 以降、launchd は `~/Library/LaunchAgents/` のファイルを単純には拾ってくれない。**Background Item Management（BTM）** という新しい層があり、ここに登録されていない LaunchAgent は launchd が起動を許可しない。

BTM への登録は `launchctl load -w`（または `launchctl bootstrap`）で行う。これを呼ばずにファイルだけ置いても、登録されないので無効。

### 教訓

`launchctl load -w` は避けられない。重複プロセス問題は前項の「重複検知 + 後発組 exit」で対応する。

確認手段：

```bash
# 登録されているか
launchctl list | grep com.local.enja-switcher
# システム設定 > 一般 > ログイン項目 > バックグラウンドでの実行を許可
# にも項目が表示されているはず
```

---

## 5. plist に `ProcessType: Interactive` を入れないとログイン時の起動が遅い

### 何が起きるか

`ProcessType` を指定しないでログインすると、ログイン直後ではなく **数十秒〜1 分遅れて**アプリが起動することがある。

### 原因

`launchd.plist` の man page より：

> ProcessType
>   If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth.

未指定だと launchd が「軽量タスク」として throttle する。ログイン直後は他の重要なプロセス（Dock, Finder, etc.）の起動が優先されるため、軽量タスクは後回しになる。

### 解決

plist に `ProcessType: Interactive` を含める：

```xml
<key>ProcessType</key>
<string>Interactive</string>
```

> Interactive jobs run with the same priority as apps, that is, higher priority than other background tasks.

これでアプリ並みの優先度で起動される。ログイン直後の遅延がほぼなくなる。

---

## 6. macOS の TCC（プライバシー権限）は signing identity に紐付く

### 何が起きるか

ad-hoc 署名（あるいは異なる証明書）で署名し直したアプリを `/Applications/` に配置すると、macOS は「**別アプリ**」と判定し、これまで付与した「アクセシビリティ」「入力監視」の権限を **破棄**する。

更に、その後元の証明書で再署名し直しても、**権限は自動復活しない**。ユーザーが System Settings から手動でマイナス → プラス で再追加しないと使えない。

### 一度経由したら不可逆

「一度でも ad-hoc を経由したら、元の証明書で再署名しても TCC は信用しない」という macOS のセキュリティ仕様。一度改変されたバイナリは署名が戻っても信用しない、という防御。

### きっかけ：codesign 失敗時の罠

`codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app` が `errSecInternalComponent` で失敗（キーチェーンロックや証明書の private key 不可視等）すると、**バイナリには `swiftc` が付与した linker-signed ad-hoc 署名が残ったまま**になる。

これに気づかず後続の `cp -r EnJaSwitcher.app /Applications/` を実行してしまうと、ad-hoc 署名のアプリが配置されて TCC 権限が破壊される。

### 教訓と防止策

ビルドコマンドを必ず `&&` で連結する：

```bash
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app && \
codesign -dvv EnJaSwitcher.app 2>&1 | grep -q "Authority=EnJaSwitcher Dev" && \
cp -r EnJaSwitcher.app /Applications/
```

`codesign -dvv | grep "Authority=..."` の **検証ステップが本質**。これで署名が ad-hoc に落ちていないことを確認してから配置する。失敗したら `cp` は走らない。

キーチェーンロックが原因なら：

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

---

## 7. macOS の権限プロンプトには 2 種類ある

### Input Monitoring（入力監視）

- アプリが `CGEventTapCreate(.cgSessionEventTap, ...)` を呼ぶ → 権限がないので失敗
- macOS の TCC が API 失敗を検知して **自発的にプロンプトを出す**
- 権限付与後、macOS は「event tap は既に作成失敗してるから restart が必要」と判断 → **「Reopen」ボタンを出す**
- ユーザーが Reopen を押すとアプリが再起動して、新たに event tap を作成 → 即動作する

### Accessibility（アクセシビリティ）

- アプリが `AXIsProcessTrustedWithOptions(options: prompt: true)` を **明示的に呼ぶ**
- macOS はプロンプトを出すが、API の戻り値で結果をアプリに返す方式
- 設計思想：「アプリが API を自分で呼んだのだから、権限付与後の挙動はアプリが自分で管理してください」
- そのため **「Reopen」ボタンは出ない**

### 影響

スクロール反転機能（`.defaultTap` モードの CGEventTap）は Accessibility が必要。アプリ起動時に作成しているので、後から Accessibility を付与しても tap は再生成されない。**ユーザーが手動でアプリを再起動しない限り反転が効かない**。

→ README / FAQ で「初回セットアップ後は念のためアプリを再起動」と案内する必要がある（Issue #17）

---

## 8. メニューバーアプリの「黒いアイコン問題」

### 何が起きるか

LaunchAgent で auto-start するアプリは、System Settings > 一般 > ログイン項目 > **「バックグラウンドでの実行を許可」** に登録される。ここに表示される項目には：

- `enja-switcher`（アプリ名ではなく **裸のバイナリ名**）
- 黒い四角に **"exec"** と書かれたデフォルトアイコン

が表示される。ユーザーから見ると「これは何？怪しいアプリ？」となる。

### 原因

LaunchAgent の plist は `.app` バンドルではなく、**バンドル内の実行ファイル（バイナリ）を直接 ProgramArguments に指定する**：

```xml
<key>ProgramArguments</key>
<array>
    <string>/Applications/EnJaSwitcher.app/Contents/MacOS/enja-switcher</string>
</array>
```

macOS は `.app` のアイコン情報（Info.plist の `CFBundleIconFile` など）を読まずに、「裸の実行ファイル」のデフォルトアイコンを使う。

### 教訓

これは仕様で回避不可能。`SMAppService` 方式なら `.app` バンドル登録なのでアイコンも正しく出るが、別のトレードオフがある。

→ アプリ自体は自己署名証明書で正しく署名されている旨を README やアプリ内ポップオーバーで説明する

---

## 9. 「Open at Login」と「Allow in the Background」の違い

System Settings > 一般 > ログイン項目 には 2 つのセクションがある：

| セクション | 登録方式 | 表示 |
|---|---|---|
| **Open at Login** | `SMAppService` API、または手動でアプリをドラッグ | アプリアイコン + アプリ名 |
| **Allow in the Background** | LaunchAgent plist | 裸のバイナリ + "exec" アイコン |

LaunchAgent 方式のアプリは「Open at Login」には表示されず、「Allow in the Background」に表示される。

ユーザーが「Open at Login」を見ても自分のアプリが無いと「何で auto-start するの？」と混乱しがち。FAQ や README で「Open at Login への手動追加は不要」と明記しておく。

---

## 10. レガシーインストールの移行 UX

### シナリオ

旧バージョン（v1.2.0 等）で「`/Library/LaunchAgents/` に手動セットアップ」を案内していたとする。新バージョン（v1.3.0）でアプリ内自動セットアップに切り替えた時、既存ユーザーは：

- /Library/LaunchAgents/ にレガシー plist がある
- 自動起動はレガシー plist 経由で動いている（ユーザーから見て困っていない）
- ただし新しい menu トグル（`~/Library/LaunchAgents/` 操作）の挙動とは噛み合わない

### 選択肢

| アプローチ | UX |
|---|---|
| 起動時にアラートで強制移行を促す | 毎起動で邪魔。レガシーで満足してる人にとってノイズ |
| ON-Toggle 試行時のみ案内 | 自然。動いてるなら何もしない、ON にしたい時だけ移行案内 |
| 何もしない | レガシーが残り続けて将来の保守負担に |

### 採用：On-Toggle 案内

「動いてるなら触らない」「明確に Launch at Login を ON にしたいユーザーにだけ案内する」というスタンス。レガシー方式でも auto-start 機能としては成立しているので、強制移行する根拠は弱い。

ポップオーバーで移行コマンドを提示し、Copy ボタン + OK ボタンで進めてもらう。

---

## 11. 移行コマンドは 1 行に統合する（コピペ前提）

### 課題

```bash
sudo launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist
sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
```

これを 2 行で表示すると、ユーザーが「同時に実行していいの？」と混乱する。`open` の標準的な貼り付けでは Enter で 1 行目だけ実行される。`&&` だと 1 行目（unload）が「not loaded」エラーで非ゼロ終了すると 2 行目（rm）が走らない。

### 解決：1 行に `;` で連結 + エラー抑制 + アプリ終了も統合

```bash
pkill -f enja-switcher 2>/dev/null; \
sudo launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null; \
sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist
```

- `pkill` で実行中アプリを終了（先にアプリ終了 → コマンド実行 → 再起動 の 3 ステップを 2 ステップに）
- `;` で順次実行（unload 失敗でも rm は走る）
- `2>/dev/null` で「not loaded」のような無害なエラーを黙らせる
- sudo パスワードは 1 回入力（macOS は同一 sudo セッション内で認証を維持）

### 教訓

ターミナル不慣れなユーザー向けにコマンドを提示する時：
- できれば 1 行
- エラー出力は抑制
- ユーザーアクション（Enter 入力）は最小回数
- 順序依存があるなら `;` （独立実行）と `&&` （前段成功時のみ）を使い分ける

---

## 12. ポップオーバー UI の選び方（NSAlert vs NSPopover）

### 区別

| | NSAlert | NSPopover |
|---|---|---|
| 表示位置 | 画面中央のモーダルダイアログ | ステータスバーアイコンに紐付く |
| 重さ | 重い（画面ブロック） | 軽い |
| 標準ボタン | OK / Cancel 等の system 配置 | 自前で配置 |
| Accessory view | サポートあり | view を自由に組める |

### 採用方針

EnJaSwitcher の CapsLock セットアップは NSPopover で実装されていた。Legacy 移行も同種の「セットアップ案内」なので、**統一感のため NSPopover に揃えた**。

NSAlert を最初使ってしまったが、メニューバーアプリの世界観（軽量で常駐、システムダイアログは重い）に合っていなかった。

### Copy ボタンを accessory view 内に置く

NSAlert / NSPopover の標準ボタンを押すとダイアログが閉じてしまう。「Copy だけしてダイアログは残したい」を実現するには：

- Copy ボタンを accessory view（または container view）内に置く
- このボタンは NSAlert / NSPopover の管理外なので、押してもダイアログは閉じない
- メイン CTA の OK ボタンだけが標準ボタンとして閉じる動作を担う

クリック時のフィードバックも便利：

```swift
@objc private func copyLegacyCommand(_ sender: NSButton) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(command, forType: .string)

    let originalTitle = sender.title
    sender.title = "Copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak sender] in
        sender?.title = originalTitle
    }
}
```

---

## 13. README 構造：開発者向けと一般ユーザー向けで内容を二重化しない

### よくある間違い

- 一般ユーザー向けに「インストール → 権限付与 → 自動起動設定」を書く
- 開発者向けにも同じ手順を「ビルド → インストール → 権限付与 → 自動起動設定」と書く
- → 重複。インストール後の挙動は同じなのに 2 箇所メンテする羽目に

### 正しい分離

**アプリの入手方法** だけが違う。それ以外は同じ：

| | 一般ユーザー | 開発者 |
|---|---|---|
| 入手 | zip ダウンロード | git clone + ソースビルド |
| インストール後 | （同じ） | （同じ） |
| 権限付与 | （同じ） | （同じ） |
| 自動起動 | （同じ） | （同じ） |

なので：

- 開発者向けセクションは **ビルド手順だけ**
- 末尾に「ここから先は一般ユーザー向けセクションを参照」と誘導

仕様や設計判断は別の「補足・参考情報」セクションを設ける（任意）。

### EnJaSwitcher の README

最終的に **6 セクション構成**：

```
1. 日本語（一般ユーザー向け）
2. 日本語（開発者向け）
3. 日本語（補足・参考情報）
4. English (General Users)
5. English (Developers)
6. English (Reference)
```

冒頭に各セクションへの目次を置き、読者が自分に合うセクションだけ読めばよい。

---

## 14. CI / リリースの順序問題

### 構成

`.github/workflows/deploy.yml` が 2 つのトリガーを持つ：

```yaml
on:
  push:
    branches: [main]
    paths:
      - website/**
      - .github/workflows/deploy.yml
  release:
    types: [published]
```

ウェブサイトはビルド時に GitHub Releases API から最新バージョンを取得して、ダウンロードボタンに反映する。

### 罠

リリース作業の順序を間違えると：

```
1. website/i18n のテキスト更新を含むコミットを push（CI 起動）
   → API は前バージョン（v1.2.0）を返す → ボタンに v1.2.0 が表示
2. zip 作って Release 公開（再度 CI 起動）
   → API が v1.3.0 を返す → ボタンに v1.3.0 が表示
```

2 回 deploy が走るし、瞬間的に古いバージョンが表示される。

### 正しい順序（コミットメッセージに `[skip ci]`）

```
1. コード変更（含む website 関連）を [skip ci] 付きで push
   → CI は走らない
2. zip 作って Release 公開
   → release: published で 1 回だけ CI が走る
   → API が v1.3.0 を返す → ボタンに v1.3.0 反映
```

GitHub Actions は commit message に `[skip ci]`, `[ci skip]`, `[no ci]` 等が含まれているとその commit の workflow をスキップする。

### 注意：environment 保護ルール

`release: published` で起動した workflow は `github.ref` がタグ名（`v1.3.0`）になる。`github-pages` environment の deployment branch policy で「タグも許可」しておかないと deploy job が即失敗する。詳細は別ドキュメント `20260508_github_pages_environment_tag_policy.md` 参照。

---

## 15. SemVer とバージョン文字列フォーマット

### 採用

`X.Y.Z` の **3 桁形式** で統一。GitHub Release タグは `vX.Y.Z`。

- 機能追加 → MINOR バンプ（1.2.0 → 1.3.0）
- バグ修正のみ → PATCH バンプ（1.3.0 → 1.3.1）
- 破壊的変更 → MAJOR バンプ

### なぜ 3 桁固定か

アップデート確認コードで `currentVersion.compare(remoteVersion, options: .numeric)` を使っていると、桁数が違うと誤判定する。例えば「1.3」と「1.2.10」を比較すると `.numeric` でも期待通り動かないケースがある。`X.Y.Z` で固定すれば安全。

---

## 16. 設計判断のスタンス：「動いてるならそのまま」

複数のシナリオで効いた共通方針：

- レガシーインストールがあるユーザー → 強制移行しない
- メニューから OFF にしたユーザーの今走ってるアプリ → 殺さず生かす
- アプリのプロセスが死んでも自動 respawn しない（KeepAlive: false） → ユーザーの Quit 意思を尊重

「**ユーザーが今困っていない状態を、技術的な都合で勝手に変えない**」というスタンス。これは macOS / GUI アプリの UX 設計で割と重要。

---

## 関連ドキュメント

- `20260508_github_pages_environment_tag_policy.md` — release タグからの deploy が environment 保護で弾かれる問題
- `CLAUDE.md` — このプロジェクト固有のビルド手順、署名ルール、LaunchAgent コードの制約

## 関連 Issue

- #13 (closed) — LaunchAgent をアプリが自動セットアップする（メニューから ON/OFF）
- #17 — 初回セットアップ時のアプリ再起動を README / website FAQ で案内
- #18 — アプリ UI の重要箇所を日本語化

## 結論

「LaunchAgent をアプリ内で管理する」というシンプルに見える要件でも、macOS の歴史的経緯（伝統的 launchctl）と現代の保護機構（Background Item Management、TCC）が絡み合って、想定外の落とし穴が多数出てきた。

特に重要な学び：

1. 一度でも ad-hoc 署名を経由するとペナルティが大きい（TCC リセット）→ ビルドコマンドは `&&` で連結する
2. `KeepAlive: true` は menu bar app では害悪（Quit が無視される）
3. `launchctl unload -w` は実行中プロセスを kill するので、uninstall ではファイル削除のみ
4. macOS 13+ では `launchctl load -w` で BTM 登録しないと auto-start が効かない
5. その副作用の重複プロセスは `NSRunningApplication` で重複検知して exit
6. リリース時は `[skip ci]` でデプロイ順序を制御する

これらは機械的なチェックでは見つかりにくく、**実機で実際にログアウト → 再ログインまで含めてテストしないと出てこない**ものが多い。手動テストの重要性を再認識した。
