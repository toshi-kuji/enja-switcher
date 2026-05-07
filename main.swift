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

    // スクロール方向反転用（マウスのみ。トラックパッドはmacOS標準のナチュラルスクロール設定に従う）
    private var scrollTap: CFMachPort?
    private var scrollRunLoopSource: CFRunLoopSource?
    var reverseMouseScroll: Bool = false {
        didSet { updateScrollTapState() }
    }

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
        setupScrollTap()
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

    // MARK: - Scroll Direction Tap

    private func updateScrollTapState() {
        if let tap = scrollTap {
            CGEvent.tapEnable(tap: tap, enable: reverseMouseScroll)
            print("Scroll event tap \(reverseMouseScroll ? "enabled" : "disabled").")
        }
    }

    /// 起動時に1回だけ呼ばれる。tapを作成し、reverseMouseScroll の初期値に従って enable/disable を設定する。
    /// tap の作成/破棄を繰り返すと権限キャッシュが破損するリスクがあるため、
    /// 以降は CGEvent.tapEnable で有効/無効を切り替える。
    func setupScrollTap() {
        let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<EventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleScrollEvent(proxy: proxy, type: type, event: event)
        }

        guard
            let t = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
        else {
            print("Failed to create scroll event tap (needs Input Monitoring permission)")
            return
        }

        self.scrollTap = t
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        self.scrollRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        // 初期状態は reverseMouseScroll に従う（デフォルト false → disabled）
        CGEvent.tapEnable(tap: t, enable: reverseMouseScroll)
        print(
            "Scroll event tap created (initially \(reverseMouseScroll ? "enabled" : "disabled")).")
    }

    private func handleScrollEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        // tapが無効化されたら自動的に再有効化（フェイルセーフ）
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.scrollTap, reverseMouseScroll {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        // 設定がOFFなら素通し（フェイルセーフ）
        if !reverseMouseScroll {
            return Unmanaged.passUnretained(event)
        }

        // マウスのみ反転。トラックパッドはmacOS標準のナチュラルスクロール設定に委ねる
        // scrollPhase または momentumPhase が非0ならトラックパッド → 素通し
        // マウスホイールはフェーズ情報を持たない（両方0）→ 反転対象
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        if scrollPhase != 0 || momentumPhase != 0 {
            return Unmanaged.passUnretained(event)
        }

        // macOS が元イベントの内部バッファを使い回すため、setIntegerValueField での
        // フィールド変更がアプリに反映されない。元イベントを破棄し、
        // 反転済みの新規スクロールイベントを生成して返す。
        let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineDeltaH = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)

        guard
            let newEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: Int32(-lineDelta),
                wheel2: Int32(lineDeltaH),
                wheel3: 0
            )
        else {
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passRetained(newEvent)
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

// MARK: - Update Checker

class UpdateChecker {
    static let releasesAPIURL =
        "https://api.github.com/repos/toshi-kuji/enja-switcher/releases/latest"
    static let releasesPageURL = "https://github.com/toshi-kuji/enja-switcher/releases/latest"

    var onUpdateAvailable: ((String) -> Void)?

    func check() {
        guard let url = URL(string: UpdateChecker.releasesAPIURL) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200,
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            else {
                return
            }

            // Strip leading "v" if present
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Validate: only digits and dots
            guard remoteVersion.allSatisfy({ $0.isNumber || $0 == "." }) else { return }

            // Compare with current version
            guard
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                    as? String
            else { return }

            if currentVersion.compare(remoteVersion, options: .numeric) == .orderedAscending {
                DispatchQueue.main.async {
                    self?.onUpdateAvailable?(remoteVersion)
                }
            }
        }.resume()
    }
}

// MARK: - LaunchAgent Management

struct LaunchAgent {
    static let label = "com.local.enja-switcher"

    static var userPlistDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents"
    }

    static var userPlistPath: String {
        return "\(userPlistDirectory)/\(label).plist"
    }

    static let systemPlistPath = "/Library/LaunchAgents/\(label).plist"

    static var binaryPath: String {
        return Bundle.main.bundlePath + "/Contents/MacOS/enja-switcher"
    }

    static func plistContents() -> String {
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
              "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(binaryPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
    }

    static var isUserInstalled: Bool {
        return FileManager.default.fileExists(atPath: userPlistPath)
    }

    static var hasLegacySystemInstall: Bool {
        return FileManager.default.fileExists(atPath: systemPlistPath)
    }

    /// 既に launchctl にロード済みかチェック。
    static var isRegisteredInLaunchctl: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// plist を ~/Library/LaunchAgents/ に書き出し、必要なら launchctl に登録する。
    /// macOS 13+ の Background Item Management に登録するために launchctl load -w が必要。
    /// この副作用で新プロセスがスポーンされるが、main の重複検知で後発組が exit するので
    /// 結果的にプロセスは 1 つのみ。既に登録済みの場合は load を呼ばない（無駄な再登録回避）。
    static func install() {
        try? FileManager.default.createDirectory(
            atPath: userPlistDirectory,
            withIntermediateDirectories: true
        )
        try? plistContents().write(
            toFile: userPlistPath,
            atomically: true,
            encoding: .utf8
        )
        if !isRegisteredInLaunchctl {
            runLaunchctl(["load", "-w", userPlistPath])
        }
    }

    /// plist ファイルを削除するだけ。launchctl unload は呼ばない
    /// （呼ぶと SIGTERM で実行中プロセスが kill されてしまう）。
    /// in-memory のジョブ登録は残るが、KeepAlive がないので影響なし。
    /// 次回ログイン時に launchd は plist を見つけられず auto-start しない。
    static func uninstall() {
        try? FileManager.default.removeItem(atPath: userPlistPath)
    }

    private static func runLaunchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to run launchctl: \(error)")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var commandMenuItem: NSMenuItem!
    var capsLockMenuItem: NSMenuItem!
    var reverseMouseMenuItem: NSMenuItem!
    var websiteMenuItem: NSMenuItem!
    var autoCheckMenuItem: NSMenuItem!
    var launchAtLoginMenuItem: NSMenuItem!
    var updateCheckTimer: Timer?

    let interceptor: EventInterceptor
    let updateChecker = UpdateChecker()

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

        // --- Reverse Mouse Scroll ---
        reverseMouseMenuItem = NSMenuItem(
            title: "Reverse Mouse Scroll", action: #selector(toggleReverseMouseScroll(_:)),
            keyEquivalent: "")
        reverseMouseMenuItem.target = self
        let reverseMouse = UserDefaults.standard.bool(forKey: "reverseMouseScroll")
        reverseMouseMenuItem.state = reverseMouse ? .on : .off
        menu.addItem(reverseMouseMenuItem)

        // --- セパレーター ---
        menu.addItem(NSMenuItem.separator())

        // --- Check for Updates Automatically ---
        autoCheckMenuItem = NSMenuItem(
            title: "Check for Updates Automatically", action: #selector(toggleAutoCheck(_:)),
            keyEquivalent: "")
        autoCheckMenuItem.target = self
        let checkEnabled =
            UserDefaults.standard.object(forKey: "checkForUpdates") == nil
            || UserDefaults.standard.bool(forKey: "checkForUpdates")
        autoCheckMenuItem.state = checkEnabled ? .on : .off
        menu.addItem(autoCheckMenuItem)

        // --- Launch at Login (Background) ---
        launchAtLoginMenuItem = NSMenuItem(
            title: "Launch at Login (Background)", action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        let launchAtLoginEnabled = setupLaunchAtLogin()
        launchAtLoginMenuItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        // --- About This App ---
        let currentVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        websiteMenuItem = NSMenuItem(
            title: "About This App (v\(currentVersion))...", action: #selector(openWebsite),
            keyEquivalent: "")
        websiteMenuItem.target = self
        menu.addItem(websiteMenuItem)

        // --- Quit ---
        let quitMenuItem = NSMenuItem(
            title: "Quit EnJaSwitcher", action: #selector(quitApp),
            keyEquivalent: "q")
        quitMenuItem.target = self
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

        // スクロール反転設定の復元（interceptor の didSet が scrollTap を有効化）
        interceptor.reverseMouseScroll = reverseMouse

        // アップデートチェックのセットアップ
        updateChecker.onUpdateAvailable = { [weak self] version in
            guard let self = self else { return }
            self.websiteMenuItem.title =
                "About This App (v\(currentVersion)) — v\(version) available"
        }

        if checkEnabled {
            scheduleUpdateChecks()
        }
    }

    private func scheduleUpdateChecks() {
        // 5秒後に初回チェック
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.updateChecker.check()
        }
        // 24時間ごとに繰り返し
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) {
            [weak self] _ in
            self?.updateChecker.check()
        }
    }

    @objc func switchMethodChanged(_ sender: NSMenuItem) {
        commandMenuItem.state = (sender == commandMenuItem) ? .on : .off
        capsLockMenuItem.state = (sender == capsLockMenuItem) ? .on : .off

        if sender == commandMenuItem {
            interceptor.currentMode = .command
            UserDefaults.standard.set("command", forKey: "switchingMethod")
        } else {
            let wasAlreadyCapsLock = interceptor.currentMode == .capsLock
            interceptor.currentMode = .capsLock
            UserDefaults.standard.set("capsLock", forKey: "switchingMethod")
            if !wasAlreadyCapsLock {
                showCapsLockSetupAlert()
            }
        }
    }

    private var capsLockPopover: NSPopover?

    private func showCapsLockSetupAlert() {
        // Close existing popover if any
        capsLockPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let viewController = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))

        let titleField = NSTextField(labelWithString: "CapsLock Mode Setup Required")
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleField.frame = NSRect(x: 16, y: 160, width: 288, height: 20)

        let bodyText = """
            To use CapsLock mode, disable the default CapsLock \
            behavior in macOS to prevent conflicts.

            System Settings > Keyboard > Keyboard Shortcuts \
            > Modifier Keys > Set "Caps Lock key" to "No Action"

            CapsLock switching will still work correctly with \
            this app's own hardware-level detection.
            """
        let bodyField = NSTextField(wrappingLabelWithString: bodyText)
        bodyField.font = NSFont.systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor
        bodyField.frame = NSRect(x: 16, y: 44, width: 288, height: 110)

        let okButton = NSButton(title: "OK", target: self, action: #selector(closeCapsLockPopover))
        okButton.bezelStyle = .rounded
        okButton.frame = NSRect(x: 228, y: 8, width: 76, height: 28)
        okButton.keyEquivalent = "\r"

        container.addSubview(titleField)
        container.addSubview(bodyField)
        container.addSubview(okButton)

        viewController.view = container
        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 320, height: 200)

        capsLockPopover = popover

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func toggleReverseMouseScroll(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        UserDefaults.standard.set(newState, forKey: "reverseMouseScroll")
        interceptor.reverseMouseScroll = newState
    }

    @objc func toggleAutoCheck(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        sender.state = newState ? .on : .off
        UserDefaults.standard.set(newState, forKey: "checkForUpdates")

        if newState {
            scheduleUpdateChecks()
        } else {
            updateCheckTimer?.invalidate()
            updateCheckTimer = nil
        }
    }

    /// 初回起動時の自動セットアップ。メニュー項目の初期状態を返す。
    private func setupLaunchAtLogin() -> Bool {
        let defaults = UserDefaults.standard

        // レガシー（/Library/LaunchAgents/）がある場合は重複登録を避けるため
        // 新方式の auto-install は走らせない。ユーザーが Launch at Login を
        // ON-toggle した時のみアラートを出して移行を促す（toggleLaunchAtLogin 側で対応）。
        // defaults.launchAtLogin は書かないことで、レガシー削除後の起動で
        // 自然に first-launch 扱いとなり auto-install が走るようにする。
        if LaunchAgent.hasLegacySystemInstall {
            return false
        }

        if defaults.object(forKey: "launchAtLogin") == nil {
            // 初回起動：自動でインストール
            LaunchAgent.install()
            defaults.set(true, forKey: "launchAtLogin")
            return true
        }

        // 2回目以降：保存された状態に従う。ON 設定だがファイルがなければ再インストール
        let enabled = defaults.bool(forKey: "launchAtLogin")
        if enabled && !LaunchAgent.isUserInstalled {
            LaunchAgent.install()
        }
        return enabled
    }

    private var pendingLegacyCommand: String?
    private var legacyMigrationPopover: NSPopover?

    @objc private func copyLegacyCommand(_ sender: NSButton) {
        guard let cmd = pendingLegacyCommand else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cmd, forType: .string)

        let originalTitle = sender.title
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak sender] in
            sender?.title = originalTitle
        }
    }

    @objc private func closeLegacyMigrationPopover() {
        legacyMigrationPopover?.close()
        legacyMigrationPopover = nil
    }

    private func showLegacyMigrationAlert() {
        let command =
            "pkill -f enja-switcher 2>/dev/null; sudo launchctl unload /Library/LaunchAgents/com.local.enja-switcher.plist 2>/dev/null; sudo rm /Library/LaunchAgents/com.local.enja-switcher.plist"
        pendingLegacyCommand = command

        // Close existing popover if any
        legacyMigrationPopover?.close()

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true

        let viewController = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 310))

        let titleField = NSTextField(labelWithString: "Legacy Install Detected")
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleField.frame = NSRect(x: 16, y: 270, width: 348, height: 20)

        let bodyText = """
            An older system-wide LaunchAgent was found at:
            /Library/LaunchAgents/com.local.enja-switcher.plist

            To migrate to the new in-app auto-setup:

            1. Run the command below in Terminal (one line). \
            This will quit EnJaSwitcher and remove the legacy install.
            2. Reopen EnJaSwitcher — auto-setup will run automatically.
            """
        let bodyField = NSTextField(wrappingLabelWithString: bodyText)
        bodyField.font = NSFont.systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor
        bodyField.frame = NSRect(x: 16, y: 130, width: 348, height: 136)

        let commandField = NSTextField(frame: NSRect(x: 16, y: 50, width: 280, height: 70))
        commandField.stringValue = command
        commandField.isEditable = false
        commandField.isSelectable = true
        commandField.isBordered = true
        commandField.drawsBackground = true
        commandField.backgroundColor = NSColor.textBackgroundColor
        commandField.font = NSFont.userFixedPitchFont(ofSize: 11)
        commandField.cell?.wraps = true
        commandField.cell?.isScrollable = false

        let copyButton = NSButton(
            title: "Copy", target: self, action: #selector(copyLegacyCommand(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.font = NSFont.systemFont(ofSize: 11)
        copyButton.frame = NSRect(x: 304, y: 96, width: 60, height: 24)

        let okButton = NSButton(
            title: "OK", target: self, action: #selector(closeLegacyMigrationPopover))
        okButton.bezelStyle = .rounded
        okButton.frame = NSRect(x: 288, y: 8, width: 76, height: 28)
        okButton.keyEquivalent = "\r"

        container.addSubview(titleField)
        container.addSubview(bodyField)
        container.addSubview(commandField)
        container.addSubview(copyButton)
        container.addSubview(okButton)

        viewController.view = container
        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 380, height: 310)

        legacyMigrationPopover = popover

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state == .off

        if newState {
            // ON にする：レガシーインストールがあれば警告のみで戻る
            if LaunchAgent.hasLegacySystemInstall {
                showLegacyMigrationAlert()
                return
            }
            LaunchAgent.install()
        } else {
            LaunchAgent.uninstall()
        }

        sender.state = newState ? .on : .off
        UserDefaults.standard.set(newState, forKey: "launchAtLogin")
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://toshi-kuji.github.io/enja-switcher/")!)
    }

    @objc private func closeCapsLockPopover() {
        capsLockPopover?.close()
        capsLockPopover = nil
    }
}

// MARK: - Main

// 重複起動防止：launchctl load -w で macOS Background Item Management に登録すると、
// 副作用として新しいプロセスがスポーンされる。既に別インスタンスが走っていれば
// この後発組をすぐ exit させ、メニューバーアイコンの重複を防ぐ。
let myPID = ProcessInfo.processInfo.processIdentifier
let runningInstances = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.local.enja-switcher"
).filter { $0.processIdentifier != pid_t(myPID) }
if !runningInstances.isEmpty {
    print("Another EnJaSwitcher instance is already running. Exiting.")
    exit(0)
}

let interceptor = EventInterceptor()
interceptor.start()

let app = NSApplication.shared
let delegate = AppDelegate(interceptor: interceptor)
app.delegate = delegate
app.run()
