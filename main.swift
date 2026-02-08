import Carbon      // TISCopyInputSourceForLanguage, TISSelectInputSource など入力ソースAPI
import Cocoa        // AXIsProcessTrustedWithOptions, CGEvent, sleep など

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

/// 指定された言語識別子（"en", "ja" など）に対応する入力ソースに切り替える。
/// TISCopyInputSourceForLanguage で言語に対応する入力ソースを取得し、
/// TISSelectInputSource で実際にアクティブにする。
/// 該当する入力ソースが見つからない場合は何もしない。
func switchInputSource(to language: String) {
    guard let source = TISCopyInputSourceForLanguage(language as CFString)?.takeRetainedValue() else {
        return
    }
    TISSelectInputSource(source)
}

/// 英語入力ソース（ABC）に切り替える。
func switchToEnglish() {
    switchInputSource(to: "en")
}

/// 日本語入力ソース（ひらがな）に切り替える。
func switchToJapanese() {
    switchInputSource(to: "ja")
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
    case none   // 判別不能（両方同時押し等）
    case left   // 左Command
    case right  // 右Command
}

/// 現在押下中のCommandキーの左右。解放時の切り替え判定に使用。
var currentCommandSide: CommandSide = .none

// MARK: - Event Flag Constants

/// 左Commandキーを示すビット（NX_DEVICELCMDKEYMASK）
let leftCommandBit: UInt64 = 0x08
/// 右Commandキーを示すビット（NX_DEVICERCMDKEYMASK）
let rightCommandBit: UInt64 = 0x10
/// Commandキー全般（左右問わず）を示すマスク
let commandMask = CGEventFlags.maskCommand.rawValue

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
        return Unmanaged.passUnretained(event)
    }

    // イベントフラグの生値を取得。修飾キーの状態がビットフィールドで格納されている。
    let rawFlags = event.flags.rawValue

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
        } else if isCommand && commandIsDown {
            // === Command押下中に修飾キーが変化 ===
            // 左右両方のCommandキーが同時に押されている場合、意図が曖昧なため切り替えを抑制する。
            let isLeft = (rawFlags & leftCommandBit) != 0
            let isRight = (rawFlags & rightCommandBit) != 0
            if isLeft && isRight {
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

        return Unmanaged.passUnretained(event)
    }

    // keyDown / keyUp イベント:
    // Commandが押されている最中に他のキーが押された場合、
    // ショートカット操作（Command+C 等）なので単押しとみなさないようフラグを立てる。
    if commandIsDown {
        otherKeyPressedDuringCommand = true
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Main

/// 監視対象のイベント種別をビットマスクで指定。
/// - flagsChanged: 修飾キー（Command等）の押下/解放
/// - keyDown / keyUp: 通常キーの押下/解放（コンビネーション検出用）
let eventMask: CGEventMask =
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue)

/// CGEventTap の作成を試みる。権限がない場合はプロンプトを表示し、5秒間隔でリトライする。
/// CGEvent.tapCreate は権限がないと nil を返すため、これを権限判定に利用する。
func createEventTap() -> CFMachPort {
    if let t = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: eventCallback,
        userInfo: nil
    ) {
        return t
    }

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
            return t
        }
    }
}

let tap = createEventTap()

/// 作成した tap を保持し、コールバック内から再有効化できるようにする。
Tap.machPort = tap

/// CFMachPort を CFRunLoop に接続するためのソースを作成し、現在の RunLoop に追加する。
/// commonModes に追加することで、モーダルパネル表示中なども含め常にイベントを受信する。
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

/// RunLoop を起動し、イベント監視を永続的に実行する。
/// この呼び出しは戻らない（プロセスが終了するまでブロックする）。
CFRunLoopRun()
