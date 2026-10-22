---
title: "Claude CodeでmacOSアプリを週末に作ったときのメモ（入力ソース切り替え）"
description: "EnJaSwitcherをClaude Codeで開発した記録。CGEventTap・IOHIDManager・TISSelectInputSourceのバグ回避・自己署名証明書によるTCC対策・LaunchAgentでハマった箇所と解決策をまとめる。"
date: 2026-04-18
---

## はじめに

週末にmacOSのメニューバー常駐アプリを作った。USキーボード環境で英語/日本語入力を切り替えるツール、[EnJaSwitcher](https://github.com/toshi-kuji/enja-switcher)。これはClaude Codeで開発し、AIが書いたコードを人間が検証し軌道修正しながら仕上げた記録です。

Swiftは少しかじっていたが、実際のアプリ構築、`CGEventTap`や`IOHIDManager`といった低レベルAPI、TCCデータベースと署名まわりには詳しくなかった。そこをAIと組んでどこまで踏み込めたか、ハマった箇所と解決策など、今後使い回せそうな知見を残しておきたいと思う。誤りがあればご指摘ください。

プロセス面・仕事観の話は[noteの記事](https://note.com/toshi_kuji/n/ne8c617810c5a)に書いたので、よければ読んでください。

扱うトピック。

- `swiftc`で単一バイナリをビルドし、手作業で`.app`バンドルを組む
- Commandキーの左右をビットフラグで識別する`CGEventTap`の実装
- CapsLockの監視を`IOHIDManager`で行う理由
- `TISSelectInputSource`の既知バグを仮想キー送信で回避
- 自己署名証明書でTCC権限を固定する運用
- LaunchAgentによる常駐化と、Terminal起動の罠

## 成果物の技術仕様

対象OSはmacOS 13以降、Apple SiliconとIntelの両方に対応。`.app`バンドルをzipで`GitHub Releases`に配置。Notarizationは行っていない。

アプリ本体は`main.swift`単一ファイル。`swiftc`に`-framework Carbon -framework Cocoa -framework IOKit`を渡してビルドする。外部ライブラリ依存なし。`Info.plist`で`LSUIElement`を指定し、アプリドックにも切替時の一覧にも現れないバックグラウンドエージェントとして動作。

入力切替の実装は二系統の組み合わせ。Commandキー左右は`CGEventTap`、CapsLockは`IOHIDManager`。入力ソースの切替自体は`TISSelectInputSource`を使わず、JISキーボードの「英数」(keyCode 102)「かな」(keyCode 104)を`CGEvent`として仮想的に送信（理由後述）。

## 1. `swiftc`単一ファイルビルドと`.app`バンドルの手作業構築

Xcodeプロジェクトを使わず`swiftc`直接ビルドを選んだ。ソースファイルとビルドコマンドだけで済むし、Zedを使いたかった。

ビルドコマンド。

```bash
swiftc -O -o enja-switcher main.swift \
  -framework Carbon -framework Cocoa -framework IOKit
```

バンドル構造。

```
EnJaSwitcher.app/
  Contents/
    Info.plist
    MacOS/
      enja-switcher            ← swiftcの出力バイナリ
    Resources/
      AppIcon.icns
```

手で組むときにハマりやすい点を挙げておく。

**`CFBundleExecutable`と実バイナリ名の対応.** `Info.plist`の`CFBundleExecutable`の値と`Contents/MacOS/`に置くバイナリ名は完全一致している必要がある。ここがずれると「アプリは起動するが何も動かない」という状態になり、ログにも大した情報が出ない。

**アイコンの`.icns`変換.** PNG一枚では足りない。`iconutil -c icns MyIcon.iconset`で複数サイズのPNGをまとめて`.icns`にする。`.iconset`ディレクトリ内のファイル名は`icon_16x16.png`、`icon_16x16@2x.png`、...と固定フォーマット。

**署名対象は`.app`バンドル全体.** `codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app`と、バンドルを丸ごと署名する。中のバイナリだけを署名するとバンドルの整合性がとれず、Gatekeeperやspctlで蹴られる。署名identityの扱い（アドホック署名ではなく固定の自己署名証明書を使う理由）は、第5章のTCC対策で詳しく扱う。

#### まとめ

> ソースが`main.swift`一本で済む規模なら`swiftc`直接ビルドで十分。`.app`バンドルは手で組めるが、`CFBundleExecutable`とバイナリ名の対応だけは慎重に。

## 2. Commandキーの左右識別と`CGEventTap`

`CGEventTap`でキーイベントを監視するが、Commandキー単体押下は`keyDown`ではなく`flagsChanged`で到着する。左右の区別は`kVK_Command` (55) と `kVK_RightCommand` (54) のkeyCode定数でも可能だが、本実装では`event.flags.rawValue`のビットフラグを使う。

```
Left Command の押下フラグビット:  0x08
Right Command の押下フラグビット: 0x10
```

これは`CGEventFlags.maskCommand`（押下中を示す公開フラグ）とは別に、生のrawValueに含まれる左右識別用のビット。公式文書化されていないが、長期間安定して機能している。

発火条件は以下。Commandキーを単独で押して離すこと、押下から離すまでの間に他のキーが一切押されていないこと。この条件を`commandIsDown`と`otherKeyPressedDuringCommand`の2つのフラグで管理する。押されているかどうかは`maskCommand`で判定し、左右どちらだったかは押した時点のビットフラグで`currentCommandSide`に記録しておく。時間制限は設けない。長押しであっても、他のキーが触られていなければ離した瞬間に発火する。

その部分のコードを示す（ログ出力や切替方式の判定は省略）。フルコードは[GitHubのmain.swift](https://github.com/toshi-kuji/enja-switcher/blob/main/main.swift)を参照。

```swift
class EventInterceptor {
    enum CommandSide { case left, right, none }

    private var tap: CFMachPort?
    private var commandIsDown = false
    private var otherKeyPressedDuringCommand = false
    private var currentCommandSide: CommandSide = .none

    func start() {
        // コールバックからは refcon 経由でインスタンスのメソッドを呼ぶ
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let interceptor = Unmanaged<EventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleEvent(proxy: proxy, type: type, event: event)
        }
        // CGEvent.tapCreate(..., callback: callback,
        //     userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        let rawFlags = event.flags.rawValue
        let leftCommandBit: UInt64 = 0x08
        let rightCommandBit: UInt64 = 0x10
        let isCommand = (rawFlags & CGEventFlags.maskCommand.rawValue) != 0

        if type == .flagsChanged {
            if isCommand && !commandIsDown {
                // 押した: 左右どちらかを記録
                commandIsDown = true
                otherKeyPressedDuringCommand = false
                let isLeft = (rawFlags & leftCommandBit) != 0
                let isRight = (rawFlags & rightCommandBit) != 0
                if isLeft && !isRight { currentCommandSide = .left }
                else if isRight && !isLeft { currentCommandSide = .right }
                else { currentCommandSide = .none }
            } else if !isCommand && commandIsDown {
                // 離した: 単独で押して離されていれば切替発火
                commandIsDown = false
                if !otherKeyPressedDuringCommand {
                    switch currentCommandSide {
                    case .left: switchToEnglish()
                    case .right: switchToJapanese()
                    case .none: break
                    }
                }
                currentCommandSide = .none
            }
            return Unmanaged.passRetained(event)
        }

        // keyDown / keyUp
        if commandIsDown { otherKeyPressedDuringCommand = true }
        return Unmanaged.passRetained(event)
    }
}
```

実装上の注意を二点。

一つ目、定数（`leftCommandBit`等）はイベント処理のメソッドの中で定義している。これをファイルのグローバルスコープに出すと、なぜかイベントタップが動作しなくなる現象に遭遇した。状態変数はクラスのプロパティに持たせ、コールバックからは`refcon`経由でインスタンスを参照している。Swiftのトップレベルコードの実行順序まわりの問題と推測しているが、根本原因までは追いきれていない。現状は動く形に留めた。

二つ目、コールバックの戻り値は`Unmanaged.passRetained(event)`にしている。`passUnretained`に変えると、イベントタップが動作しなくなった。

### CGEventTapのイベントロスト対策

`CGEventTap`はOS側の判断でタップが無効化されることがある。高負荷時やタイムアウト、ユーザーが何らかの権限操作をしたときなど。無効化されるとキー入力を取り逃がすので、イベントタップの再有効化処理を入れておく。

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap = self.tap {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return Unmanaged.passRetained(event)
}
```

`handleEvent`の冒頭でこれを処理しておけば、OS側でタップが切られても自動復帰する。長時間常駐するメニューバーアプリでは外せない。

#### まとめ

> 修飾キー単体の押下は`flagsChanged`で来る。左右識別は`event.flags.rawValue`のビットフラグが手堅い。`CGEventTap`は黙って切られることがあるので、`.tapDisabledByTimeout`と`.tapDisabledByUserInput`の復帰処理を入れておく。

## 3. CapsLockと`IOHIDManager`

切替方式の二つ目として、CapsLockの単押しで英数、二度押しで日本語という方式を入れた。ここでは`CGEventTap`を使わず`IOHIDManager`を採用している。

理由は、ユーザーがシステム設定で「Caps Lockキーの動作」を「アクションなし」に設定していた場合、`CGEventTap`にはイベントが到着しないから。CapsLockをControlやEscapeに再割り当てしたり無効化している人は多く、その状態で切替が動かないのは許容できない。

`IOHIDManager`はUSB HIDレベルで入力を直接取る。OSの「Caps Lockを無効化」設定より下のレイヤーで動くので、システム設定に影響されない。

実装の概略。

```swift
let hidManager = IOHIDManagerCreate(kCFAllocatorDefault,
                                    IOOptionBits(kIOHIDOptionsTypeNone))

let matchingDict: [String: Any] = [
    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
]
IOHIDManagerSetDeviceMatching(hidManager, matchingDict as CFDictionary)

IOHIDManagerRegisterInputValueCallback(hidManager, { ctx, result, sender, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let pressed = IOHIDValueGetIntegerValue(value) == 1

    // usagePage == 0x07 (Keyboard) かつ usage == 0x39 (CapsLock) を検出
    // 単押しと二度押しの判定を時間差（0.3秒）で行う
}, nil)

IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(),
                                CFRunLoopMode.commonModes.rawValue)
IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
```

`matchingDict`でキーボードデバイスに絞っておく。これをしないとマウスやトラックパッドからも`inputValueCallback`が呼ばれて余計な処理が走る。

### 権限要求

`IOHIDManager`で生の入力を取るには、macOSの`Input Monitoring`権限が必要になる。`System Settings > Privacy & Security > Input Monitoring`でアプリを許可してもらう。初回起動時に権限ダイアログを出す仕組みは組み込まれないので、アプリ側でメニュー等から設定画面を開く導線を用意しておくとよい。

#### まとめ

> キーボード入力をシステム設定に影響されず捕まえたい場合、`CGEventTap`より下の`IOHIDManager`を検討する。`Input Monitoring`権限の付与が必要。マッチング辞書でキーボードデバイスに絞ることを忘れない。

## 4. `TISSelectInputSource`のバグと仮想キー送信による回避

本記事の中心。同じ症状で検索で辿り着いた人が最短で解決策に行けるよう、症状→切り分け→回避策の順で書く。

### 症状

- バックグラウンドエージェントから`TISSelectInputSource`で日本語入力に切り替えると、**メニューバーの入力インジケータは「あ」に変わるが、実際の入力状態はABCのまま**
- キーを打つと半角英字が入る
- フォアグラウンドアプリから呼ぶと正常に動作する
- バックグラウンドから呼んだ場合も、**英語への切替は動く**
- 日本語への切替だけが非対称に壊れる

以下がAIが最初に提示してきた実装。公式APIとしては正しい。

```swift
func switchToJapanese() {
    guard let sourcesCF = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
    let sources = sourcesCF as! [TISInputSource]
    for source in sources {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        if id == "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese" {
            TISSelectInputSource(source)
            break
        }
    }
}
```

### 切り分けフロー

AIが最初に返してきた仮説を潰していく。

1. **Accessibility/Input Monitoring権限の未付与?** → 両方付与済み。外して付け直しても症状変わらず。該当しない。
2. **呼び出しタイミングが早すぎる?** → `DispatchQueue.main.async`で数百ミリ秒〜数秒遅らせても症状同じ。該当しない。
3. **入力ソースIDが間違っている?** → 手動切替時に同じIDで認識されている。該当しない。
4. **非対称性に着目** → 英語への切替は動く、日本語だけ壊れる。この非対称はAPI利用方法の問題では説明できない。OS側のバグの可能性が高い。

ここまで切り分けた時点で、macOSの既知バグである[openradar #5021326444232704](https://openradar.appspot.com/radar?id=5021326444232704)に該当すると判断した。バックグラウンドからの`TISSelectInputSource`で日本語への切替だけが破綻する、数年来の不具合である。

### 回避策: 仮想キー送信

JISキーボードには「英数」(keyCode 102)「かな」(keyCode 104)が物理キーとして存在する。OSはこのキー入力を受け取ると入力ソースを切り替える。この経路は`TISSelectInputSource`より下のレイヤーで処理されるため、例のバグの影響を受けない。

USキーボードにこれらの物理キーは存在しないが、OSは「keyCode 102が押された」という仮想イベントが届けば物理キーの有無に関係なく入力ソースを切り替える。`CGEvent`でこの仮想イベントを合成して送信すれば、バグを迂回できる。

そのまま使い回せるコード。

```swift
func sendVirtualKey(_ keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source,
                          virtualKey: keyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source,
                        virtualKey: keyCode, keyDown: false)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

func switchToEnglish()  { sendVirtualKey(102) }
func switchToJapanese() { sendVirtualKey(104) }
```

この実装はバックグラウンドからの呼び出しでも、メニューバー表示と実際の入力状態が同期する。

### 副作用の検討

仮想キー送信は他キーの状態を壊さないかが気になる点。実験した範囲では、以下が確認できている。

- 修飾キー状態（Shift押下中など）はリセットされない。`CGEventSource(stateID: .hidSystemState)`を使うことで、他アプリのキー入力状態を汚さない
- dead keyの入力待ち状態にあるときは挙動が不安定になる可能性がある。IMEがdead key入力中かどうかは外部から判別が難しく、完全なハンドリングは諦めている
- 他の入力ソース（中国語、韓国語など）がアクティブな状態から`keyCode 102/104`を送ると、意図しない挙動になる可能性がある。EnJaSwitcherは英数/かな切替専用という前提で割り切った

#### まとめ

> OSの公式APIに非対称なバグを見つけたら、API層より一段下のレイヤー（今回なら仮想キーイベント）で代替する発想を持つ。AIはAPIドキュメントに沿った一般解は出せるが、エッジケースのバグは人間が症状を観察して切り分けるしかない。

## 5. 自己署名証明書とTCCデータベース、権限の永続化

アプリが`Accessibility`と`Input Monitoring`の両方を要求するため、ビルドのたびに権限再設定が発生すると使い勝手が悪い。これを避ける運用がTCC対策。

macOSのTCC(Transparency, Consent, and Control)データベースは、アプリを**署名のidentity**で識別する。同じidentityで署名されたバイナリは「同じアプリ」として扱われ、権限が継続する。署名が変わればTCCから別アプリと見なされ、権限は再付与が必要になる。

最初は`codesign --sign -`のアドホック署名でビルドしていたが、この署名はビルドごとに異なるidentityを生成するため、ビルドのたびにTCCが別アプリ扱いにしてきて、`Accessibility`と`Input Monitoring`の権限を毎回付け直す羽目になった。開発中にこれが続くと作業が進まない。

解決策は、キーチェーンで作った固定の自己署名証明書で署名すること。Notarizationを取らない個人配布なら、この運用で十分実用的。

1. キーチェーンアクセス → 証明書アシスタント → 証明書を作成
2. 名前: `EnJaSwitcher Dev`（任意）、固有名のタイプ: 自己署名ルート、証明書のタイプ: コード署名
3. 作成後、ビルドごとにこの証明書で署名する

```bash
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
```

署名状態は`codesign`で確認できる。

```bash
codesign -d --verbose=4 EnJaSwitcher.app
```

`Authority=EnJaSwitcher Dev`が出ていれば意図した証明書で署名されている。

一度証明書を作り直したり、うっかり署名を省略してビルドしてしまうと、TCCはそれを別アプリと判定する。この場合は`System Settings`の権限リストから古いエントリをマイナスボタンで削除し、プラスボタンで新しい`.app`を追加する手順が必要になる。

#### まとめ

> TCCはアプリを署名identityで識別する。自己署名証明書を一度作り、全ビルドを同じ証明書で署名することで、開発中に権限を毎回付け直す苦行を避けられる。

## 6. LaunchAgentと権限誤付与の罠

ログイン時の自動起動はLaunchAgentで実現する。v1.3.0からは、メニューの「Launch at Login (Background)」をオンにすると、アプリ自身が`~/Library/LaunchAgents/com.local.enja-switcher.plist`を書き出して登録する。書き出すplistは以下（`ProgramArguments`には実行中の`.app`内のバイナリのパスが入る）。

```xml
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
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

### `KeepAlive`は入れない

`KeepAlive = true`にすると、プロセスが終了するたびに`launchd`が再起動する。クラッシュからの自動復帰には便利だが、ユーザーがメニューからQuitしても即座に立ち上がり直し、アプリを終了できなくなる。メニューから終了できるべき常駐アプリでは入れない。

### `ProcessType: Interactive`

これがないと`launchd`はジョブを軽量なバックグラウンドタスクとして扱ってthrottleし、ログイン直後ではなく数十秒〜1分遅れて起動することがある。ユーザーが直接操作するアプリなので`Interactive`を指定する。

### 登録と解除

macOS 13以降は、plistをディスクに置くだけではログイン時に起動しない。`launchctl`で登録し、macOSのBackground Item Managementに載せる必要がある。アプリは未登録の場合に限り、以下を実行している。

```bash
launchctl load -w ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

状態確認。

```bash
launchctl list | grep enja-switcher
```

この登録には副作用がある。`RunAtLoad`が`true`なので、`load`した瞬間に`launchd`が新しいプロセスを起動し、二重起動になる。そこで起動直後に、同じBundle IDのプロセスが既に動いていないかを確認し、後から起動した側を終了させている。

```swift
let myPID = ProcessInfo.processInfo.processIdentifier
let runningInstances = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.local.enja-switcher"
).filter { $0.processIdentifier != pid_t(myPID) }
if !runningInstances.isEmpty {
    exit(0)
}
```

解除（メニューをオフ）はplistファイルを削除するだけにしている。`launchctl unload`を呼ぶと、アプリ自身が`launchd`の管理下で動いている場合にSIGTERMが届き、実行中のアプリが終了してしまう。ファイルを消せば次回ログイン時には起動しないし、`KeepAlive`がないのでメモリ上に残った登録も悪さをしない。

### Terminalから起動すると権限が誤付与される罠

開発中にバイナリをTerminalから直接実行するとハマる。

```bash
# これをやると Accessibility/Input Monitoring 権限が Terminal.app に付与されてしまう
./EnJaSwitcher.app/Contents/MacOS/enja-switcher
```

macOSは親プロセスに対して権限を要求する設計なので、Terminalから起動したプロセスの権限要求は`Terminal.app`宛てになる。結果、`EnJaSwitcher.app`には権限が付かず、本番（LaunchAgent経由の起動）では動かない。

正しくは`open`コマンドで起動する。

```bash
open /Applications/EnJaSwitcher.app
```

LaunchAgentは`launchd`が直接バイナリを起動するため、親プロセス問題は発生しない。権限は正しく`EnJaSwitcher.app`に付与される。

#### まとめ

> LaunchAgentで常駐させるなら、`KeepAlive`は入れず`ProcessType: Interactive`を指定する。macOS 13以降は`launchctl load -w`で登録しないとログイン時に起動しないが、`RunAtLoad`で二重起動するので重複起動の検知を入れておく。解除はplistの削除だけにする。開発中にTerminalからバイナリを直接実行すると権限が`Terminal.app`に付いてしまうので、`open`コマンドを使うこと。

## 全体を通しての学び

この開発で強く感じたのは、**AIを使いこなすにはシステムのレイヤー構造に対する感覚が効く**ということ。

`IOHIDManager`を発見した経緯と、`TISSelectInputSource`のバグを仮想キー送信で回避した経緯は、どちらも同じ構造だった。「OSの公開APIより下のレイヤーに何かあるはず」「この処理はもっと下で扱われているはず」という勘所が、AIへの問いの質を決める。問いが適切なら、AIは知識を提供する。問いが甘ければ、もっともらしい一般解が返ってきて、それで止まる。

特定のAPIの知識そのものはAIに任せられる。任せられないのは、どこにどんな層があるかという全体の地図を持つこと。コンピュータサイエンスの基礎、OSの仕組み、IO層の構造、このあたりの土台があるほど、AIから引き出せるものが増える。

AIとの協業でコードを書かせる時代においても、基礎の重要性は下がらない。むしろ上がる気がしている。

---

### リポジトリ

- [EnJaSwitcher (GitHub)](https://github.com/toshi-kuji/enja-switcher)
- [ランディングページ](https://toshi-kuji.github.io/enja-switcher/)

### 関連記事

- [note: 週末にアプリをリリースした。コードは一切書いていない。](https://note.com/toshi_kuji/n/ne8c617810c5a) - 同じ開発のプロセス・仕事観について書いた記事
