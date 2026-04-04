import Carbon  // TISCopyInputSourceForLanguage, TISSelectInputSource など入力ソースAPI
import Cocoa  // AXIsProcessTrustedWithOptions, CGEvent, sleep など

// MARK: - Input Monitoring Permission Check

/// 入力監視の権限プロンプトを表示する。
/// AXIsProcessTrustedWithOptions に kAXTrustedCheckOptionPrompt: true を渡すと、
/// macOSが自動でシステム設定の入力監視画面を開く。
/// 実際の権限有無は CGEvent.tapCreate の成否で判定する（より確実）。
func promptInputMonitoringPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

// MARK: - Input Source Switching

/// 仮想キーコードを送信して入力ソースを切り替える。
/// TISSelectInputSource のバグ（一部のアプリで入力ソースが反映されない問題）を回避するため、
/// JISキーボードの「英数」(102) と「かな」(104) キーの押下イベントをシミュレートする。
func postKey(_ key: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

/// 英語入力ソース（ABC）に切り替える。
func switchToEnglish() {
    postKey(102)  // JIS「英数」キー
}

/// 日本語入力ソース（ひらがな）に切り替える。
func switchToJapanese() {
    postKey(104)  // JIS「かな」キー
}

// MARK: - Tap State

/// Commandキーを押している間に他のキーが押されたかどうか。
/// true の場合、Command+C 等のショートカット操作なので切り替えを行わない。
var otherKeyPressedDuringCommand = false

/// Commandキーが現在押下中かどうか。
/// flagsChanged イベントで押下/解放を追跡する。
var commandIsDown = false

/// 現在押されているCommandキーが左右どちらかを表す。
/// flagsChanged の押下時にビットマスクから判別し、解放時に参照する。
/// 解放イベントではサイドビットがクリアされるため、押下時に記録しておく必要がある。
enum CommandSide {
    case none  // 判別不能（両方同時押し等）
    case left  // 左Command
    case right  // 右Command
}

/// 現在押下中のCommandキーの左右。解放時の切り替え判定に使用。
var currentCommandSide: CommandSide = .none

// MARK: - Event Tap

/// CGEventTap の CFMachPort 参照を保持するための名前空間。
/// tapDisabledByTimeout 時に再有効化するためにコールバック内からアクセスする。
/// case なしの enum を使うことでインスタンス化を防いでいる。
enum Tap {
    static var machPort: CFMachPort?
}

/// CGEventTap に登録するコールバック関数。
/// すべてのキーボードイベント（修飾キー変更・キー押下・キー解放）を受け取り、
/// Commandキーの単押し（押して離す）を検出して入力ソースを切り替える。
/// listenOnly モードのため、イベント自体は変更せずそのまま返す。
let eventCallback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
    // システムがタイムアウトやユーザー操作でタップを無効化した場合に再有効化する。
    // 高負荷時などに発生しうる。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = Tap.machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    // イベントフラグの生値を取得。修飾キーの状態がビットフィールドで格納されている。
    let rawFlags = event.flags.rawValue

    // 左Commandキーを示すビット（NX_DEVICELCMDKEYMASK）
    let leftCommandBit: UInt64 = 0x08
    // 右Commandキーを示すビット（NX_DEVICERCMDKEYMASK）
    let rightCommandBit: UInt64 = 0x10
    // Commandキー全般（左右問わず）を示すマスク
    let commandMask = CGEventFlags.maskCommand.rawValue

    // 現在Commandキーが押されているかどうか
    let isCommand = (rawFlags & commandMask) != 0

    // flagsChanged: 修飾キー（Command, Shift, Option, Control等）の状態変化時に発火
    if type == .flagsChanged {
        if isCommand && !commandIsDown {
            // === Command押下の瞬間 ===
            commandIsDown = true
            otherKeyPressedDuringCommand = false

            // サイドビットで左右を判別。
            // 押下時のみサイドビットが立つ（解放時はクリアされる）ため、ここで記録する。
            let isLeft = (rawFlags & leftCommandBit) != 0
            let isRight = (rawFlags & rightCommandBit) != 0

            if isLeft && !isRight {
                currentCommandSide = .left
            } else if isRight && !isLeft {
                currentCommandSide = .right
            } else {
                // 両方同時押し等、判別不能
                currentCommandSide = .none
            }
        } else if !isCommand && commandIsDown {
            // === Command解放の瞬間 ===
            commandIsDown = false

            // 他のキーが押されていない = Commandの単押し → 切り替え発動
            if !otherKeyPressedDuringCommand {
                switch currentCommandSide {
                case .left:
                    switchToEnglish()
                case .right:
                    switchToJapanese()
                case .none:
                    break
                }
            }

            currentCommandSide = .none
        }

        return Unmanaged.passRetained(event)
    }

    // keyDown / keyUp イベント:
    // Commandが押されている最中に他のキーが押された場合、
    // ショートカット操作（Command+C 等）なので単押しとみなさないようフラグを立てる。
    if commandIsDown {
        otherKeyPressedDuringCommand = true
    }

    return Unmanaged.passRetained(event)
}

// MARK: - Main

/// 監視対象のイベント種別をビットマスクで指定。
/// - flagsChanged: 修飾キー（Command等）の押下/解放
/// - keyDown / keyUp: 通常キーの押下/解放（コンビネーション検出用）
let eventMask: CGEventMask =
    (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.keyUp.rawValue)

/// CGEventTap の作成を試みる。権限がない場合はプロンプトを表示し、5秒間隔でリトライする。
/// CGEvent.tapCreate は権限がないと nil を返すため、これを権限判定に利用する。
var tap: CFMachPort!

if let t = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: eventCallback,
    userInfo: nil
) {
    tap = t
} else {
    // 権限がないのでプロンプトを表示してリトライ
    promptInputMonitoringPermission()

    while true {
        sleep(5)
        if let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: nil
        ) {
            tap = t
            break
        }
    }
}

/// 作成した tap を保持し、コールバック内から再有効化できるようにする。
Tap.machPort = tap

/// CFMachPort を CFRunLoop に接続するためのソースを作成し、現在の RunLoop に追加する。
/// commonModes に追加することで、モーダルパネル表示中なども含め常にイベントを受信する。
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

/// RunLoop を起動し、イベント監視を永続的に実行する。
/// 以前は CFRunLoopRun() を使用していたが、GUIアプリ化に伴い NSApplication を起動する。

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    // UIの各項目への参照を保持
    var commandMenuItem: NSMenuItem!
    var capsLockMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("EnJaSwitcher GUI started.")

        // 1. システムのメニューバーにステータスアイテム（領域）を作成
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 2. メニューバーアイコンを設定（シンプルなテキスト "E/J" を使用）
        if let button = statusItem.button {
            button.title = "E/J"
        }

        // 3. メニューの作成と項目の追加
        let menu = NSMenu()

        // --- Option 1: Left/Right Command ---
        commandMenuItem = NSMenuItem(
            title: "Left/Right Command", action: #selector(switchMethodChanged(_:)),
            keyEquivalent: "")
        commandMenuItem.target = self
        commandMenuItem.state = .on  // デフォルトはCommand方式
        menu.addItem(commandMenuItem)

        // --- Option 2: CapsLock ---
        capsLockMenuItem = NSMenuItem(
            title: "CapsLock (Single/Double)", action: #selector(switchMethodChanged(_:)),
            keyEquivalent: "")
        capsLockMenuItem.target = self
        capsLockMenuItem.state = .off  // まだ実装前だがUIとしては用意する
        menu.addItem(capsLockMenuItem)

        // --- セパレーター ---
        menu.addItem(NSMenuItem.separator())

        // --- Quit ---
        let quitMenuItem = NSMenuItem(
            title: "Quit EnJaSwitcher", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitMenuItem)

        // メニューをステータスアイテムに紐付け
        statusItem.menu = menu
    }

    // メニュー項目がクリックされたときのアクション
    @objc func switchMethodChanged(_ sender: NSMenuItem) {
        // 選択された項目にチェックマークを入れ、それ以外を外す
        commandMenuItem.state = (sender == commandMenuItem) ? .on : .off
        capsLockMenuItem.state = (sender == capsLockMenuItem) ? .on : .off

        // 将来のフェーズで、ここで実際の切り替えロジックを切り替える
        print("Selected switching method changed to: \(sender.title)")
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
