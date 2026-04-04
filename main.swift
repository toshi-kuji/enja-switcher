import Carbon  // TISCopyInputSourceForLanguage, TISSelectInputSource など入力ソースAPI
import Cocoa  // AXIsProcessTrustedWithOptions, CGEvent, sleep など
import IOKit.hid  // IOHIDManager for hardware-level CapsLock detection

// MARK: - Input Monitoring Permission Check

func promptInputMonitoringPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

// MARK: - Input Source Switching

func postKey(_ key: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

func switchToEnglish() {
    postKey(102)  // JIS「英数」キー
}

func switchToJapanese() {
    postKey(104)  // JIS「かな」キー
}

// MARK: - Event Interceptor

class EventInterceptor {
    enum SwitchingMode {
        case command
        case capsLock
    }

    var currentMode: SwitchingMode = .command {
        didSet {
            print("Switching mode changed to: \(currentMode)")
        }
    }

    enum CommandSide {
        case none
        case left
        case right
    }

    private var commandIsDown = false
    private var otherKeyPressedDuringCommand = false
    private var currentCommandSide: CommandSide = .none

    // CapsLock監視用の状態変数
    private var capsLockIsOn = false
    private var lastCapsLockPressTime: CFAbsoluteTime = 0
    private let doublePressThreshold: CFAbsoluteTime = 0.3
    private var pendingSinglePressTimer: Timer?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let interceptor = Unmanaged<EventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleEvent(proxy: proxy, type: type, event: event)
        }

        if let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) {
            self.tap = t
            self.enableTapAndHIDManager()
        } else {
            promptInputMonitoringPermission()

            // 権限が付与されるまでTimerを使って非同期で待機（AppKitのメインスレッドをブロックしない）
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                if let t = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: eventMask,
                    callback: callback,
                    userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                ) {
                    self.tap = t
                    self.enableTapAndHIDManager()
                    timer.invalidate()
                    print("Permission granted. Event taps enabled.")
                }
            }
        }
    }

    private func enableTapAndHIDManager() {
        if let tap = self.tap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        setupHIDManager()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rawFlags = event.flags.rawValue

        // --- 調査用ログ ---
        // ターミナルから起動した時にどのキーが検知されたかを出力します
        if type == .flagsChanged || type == .keyDown || type == .keyUp {
            print(
                "Detected event type: \(type.rawValue), keyCode: \(keyCode), rawFlags: \(rawFlags)")
        }

        let leftCommandBit: UInt64 = 0x08
        let rightCommandBit: UInt64 = 0x10
        let commandMask = CGEventFlags.maskCommand.rawValue
        let isCommand = (rawFlags & commandMask) != 0

        if type == .flagsChanged {
            if currentMode == .command {
                if isCommand && !commandIsDown {
                    commandIsDown = true
                    otherKeyPressedDuringCommand = false

                    let isLeft = (rawFlags & leftCommandBit) != 0
                    let isRight = (rawFlags & rightCommandBit) != 0

                    if isLeft && !isRight {
                        currentCommandSide = .left
                    } else if isRight && !isLeft {
                        currentCommandSide = .right
                    } else {
                        currentCommandSide = .none
                    }
                } else if !isCommand && commandIsDown {
                    commandIsDown = false

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
            }
            return Unmanaged.passRetained(event)
        }
        if commandIsDown {
            otherKeyPressedDuringCommand = true
        }

        return Unmanaged.passRetained(event)
    }

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let hidManager = hidManager else { return }

        let keyboardDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(hidManager, keyboardDict as CFDictionary)

        let callback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let interceptor = Unmanaged<EventInterceptor>.fromOpaque(context).takeUnretainedValue()
            interceptor.handleHIDValue(value: value)
        }

        IOHIDManagerRegisterInputValueCallback(
            hidManager, callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDManagerScheduleWithRunLoop(
            hidManager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handleHIDValue(value: IOHIDValue) {
        if currentMode != .capsLock { return }

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        // 0x07 is Keyboard, 0x39 is CapsLock
        if usagePage == 0x07 && usage == 0x39 {
            let intValue = IOHIDValueGetIntegerValue(value)

            // 1 is Down, 0 is Up
            if intValue == 1 {
                let currentTime = CFAbsoluteTimeGetCurrent()
                let timeSinceLastPress = currentTime - lastCapsLockPressTime

                if pendingSinglePressTimer != nil && timeSinceLastPress <= doublePressThreshold {
                    // ダブルプレス：待機中のシングルプレスタイマーをキャンセルして日本語へ切り替え
                    pendingSinglePressTimer?.invalidate()
                    pendingSinglePressTimer = nil
                    switchToJapanese()
                    lastCapsLockPressTime = 0
                } else {
                    // 1回目の押下：0.3s待ってからシングルプレスと判定して英語へ切り替え
                    pendingSinglePressTimer?.invalidate()
                    lastCapsLockPressTime = currentTime
                    pendingSinglePressTimer = Timer.scheduledTimer(
                        withTimeInterval: doublePressThreshold, repeats: false
                    ) { [weak self] _ in
                        switchToEnglish()
                        self?.pendingSinglePressTimer = nil
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var commandMenuItem: NSMenuItem!
    var capsLockMenuItem: NSMenuItem!

    let interceptor: EventInterceptor

    init(interceptor: EventInterceptor) {
        self.interceptor = interceptor
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("EnJaSwitcher GUI started.")

        // 1. システムのメニューバーにステータスアイテム（領域）を作成
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 2. メニューバーアイコンを設定（AppIcon をリサイズして使用）
        if let button = statusItem.button {
            if let icon = NSImage(named: "AppIcon") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.title = "E/J"
            }
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

        // 状態の復元 (UserDefaults)
        let savedMethod = UserDefaults.standard.string(forKey: "switchingMethod")
        if savedMethod == "capsLock" {
            commandMenuItem.state = .off
            capsLockMenuItem.state = .on
            interceptor.currentMode = .capsLock
        } else {
            // デフォルトはCommand方式
            commandMenuItem.state = .on
            capsLockMenuItem.state = .off
            interceptor.currentMode = .command
        }
    }

    @objc func switchMethodChanged(_ sender: NSMenuItem) {
        commandMenuItem.state = (sender == commandMenuItem) ? .on : .off
        capsLockMenuItem.state = (sender == capsLockMenuItem) ? .on : .off

        if sender == commandMenuItem {
            interceptor.currentMode = .command
            UserDefaults.standard.set("command", forKey: "switchingMethod")
        } else {
            interceptor.currentMode = .capsLock
            UserDefaults.standard.set("capsLock", forKey: "switchingMethod")
        }
    }
}

// MARK: - Main

let interceptor = EventInterceptor()
interceptor.start()

let app = NSApplication.shared
let delegate = AppDelegate(interceptor: interceptor)
app.delegate = delegate
app.run()
