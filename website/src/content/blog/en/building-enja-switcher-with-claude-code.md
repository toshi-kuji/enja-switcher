---
title: "Notes from Building a macOS App over a Weekend with Claude Code (Input Source Switching)"
description: "How EnJaSwitcher was built with Claude Code: CGEventTap, IOHIDManager, working around a TISSelectInputSource bug, keeping TCC permissions with a self-signed certificate, and LaunchAgent pitfalls."
date: 2026-10-22
---

## Introduction

Over a weekend I built a macOS menu bar app: [EnJaSwitcher](https://github.com/toshi-kuji/enja-switcher), a tool for switching between English and Japanese input on a US keyboard. I developed it with Claude Code, and this is a record of how I verified and course-corrected the code the AI wrote until it was finished.

I had dabbled in Swift, but I was not familiar with building a real app, low-level APIs such as `CGEventTap` and `IOHIDManager`, or the TCC database and code signing. I want to record how far I could get into those areas by pairing with AI, along with the pitfalls I hit and how I solved them, so the knowledge can be reused later. If you find any mistakes, please let me know.

I wrote about the process and my view of the work in [an article on note](https://note.com/toshi_kuji/n/ne8c617810c5a) (in Japanese), if you are interested.

Topics covered:

- Building a single binary with `swiftc` and assembling the `.app` bundle by hand
- A `CGEventTap` implementation that tells left and right Command apart by bit flags
- Why CapsLock is monitored with `IOHIDManager`
- Working around a known `TISSelectInputSource` bug by sending virtual keys
- Keeping TCC permissions stable with a self-signed certificate
- Running as a resident app with a LaunchAgent, and the trap of launching from Terminal

## Technical specs

Targets macOS 13 or later, on both Apple Silicon and Intel. The `.app` bundle is distributed as a zip on `GitHub Releases`. It is not notarized.

The app itself is a single file, `main.swift`. It is built by passing `-framework Carbon -framework Cocoa -framework IOKit` to `swiftc`. There are no external library dependencies. `LSUIElement` is set in `Info.plist`, so it runs as a background agent that appears neither in the Dock nor in the app switcher.

Input switching combines two mechanisms: `CGEventTap` for left/right Command, and `IOHIDManager` for CapsLock. The actual input source switch does not use `TISSelectInputSource`; instead it sends the JIS keyboard's "Eisuu" (keyCode 102) and "Kana" (keyCode 104) keys as virtual `CGEvent`s (the reason is explained below).

## 1. Single-file `swiftc` builds and a hand-assembled `.app` bundle

I chose to build directly with `swiftc` rather than use an Xcode project. All it takes is the source file and a build command, and I wanted to use Zed.

The build command:

```bash
swiftc -O -o enja-switcher main.swift \
  -framework Carbon -framework Cocoa -framework IOKit
```

The bundle structure:

```
EnJaSwitcher.app/
  Contents/
    Info.plist
    MacOS/
      enja-switcher            ← binary output by swiftc
    Resources/
      AppIcon.icns
```

Here are the points that are easy to get wrong when assembling it by hand.

**`CFBundleExecutable` must match the actual binary name.** The value of `CFBundleExecutable` in `Info.plist` must exactly match the name of the binary in `Contents/MacOS/`. If they differ, you get an app that launches but does nothing, and the logs tell you very little.

**Converting the icon to `.icns`.** A single PNG is not enough. Use `iconutil -c icns MyIcon.iconset` to combine PNGs of several sizes into an `.icns` file. The file names inside the `.iconset` directory follow a fixed format: `icon_16x16.png`, `icon_16x16@2x.png`, and so on.

**Sign the whole `.app` bundle.** Sign the entire bundle with `codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app`. If you sign only the binary inside, the bundle is not consistent and Gatekeeper or spctl rejects it. How the signing identity is handled (why a fixed self-signed certificate is used instead of ad-hoc signing) is covered in detail in section 5 on TCC.

#### Summary

> If your source fits in a single `main.swift`, building directly with `swiftc` is enough. You can assemble the `.app` bundle by hand, but be careful that `CFBundleExecutable` matches the binary name.

## 2. Telling left and right Command apart with `CGEventTap`

Key events are monitored with `CGEventTap`, but pressing the Command key on its own arrives as `flagsChanged`, not `keyDown`. Left and right can also be distinguished by the keyCode constants `kVK_Command` (55) and `kVK_RightCommand` (54), but this implementation uses bit flags in `event.flags.rawValue`.

```
Left Command pressed flag bit:  0x08
Right Command pressed flag bit: 0x10
```

These are bits in the raw rawValue that identify left and right, separate from `CGEventFlags.maskCommand` (the public flag meaning "Command is held"). They are not officially documented, but they have worked reliably for a long time.

The trigger conditions are: the Command key is pressed and released on its own, and no other key is pressed between press and release. These conditions are tracked with two flags, `commandIsDown` and `otherKeyPressedDuringCommand`. Whether Command is held is checked with `maskCommand`, and which side was pressed is recorded in `currentCommandSide` from the bit flags at the moment of the press. There is no time limit. Even a long press triggers on release, as long as no other key was touched.

Here is that part of the code (logging and the switching-mode check are omitted). See [main.swift on GitHub](https://github.com/toshi-kuji/enja-switcher/blob/main/main.swift) for the full code.

```swift
class EventInterceptor {
    enum CommandSide { case left, right, none }

    private var tap: CFMachPort?
    private var commandIsDown = false
    private var otherKeyPressedDuringCommand = false
    private var currentCommandSide: CommandSide = .none

    func start() {
        // The callback reaches the instance method through refcon
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
                // Pressed: record which side
                commandIsDown = true
                otherKeyPressedDuringCommand = false
                let isLeft = (rawFlags & leftCommandBit) != 0
                let isRight = (rawFlags & rightCommandBit) != 0
                if isLeft && !isRight { currentCommandSide = .left }
                else if isRight && !isLeft { currentCommandSide = .right }
                else { currentCommandSide = .none }
            } else if !isCommand && commandIsDown {
                // Released: trigger the switch if it was pressed on its own
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

Two implementation notes.

First, the constants (`leftCommandBit` and so on) are defined inside the event-handling method. When I moved them to the file's global scope, the event tap mysteriously stopped working. The state variables are properties of the class, and the callback reaches the instance through `refcon`. I suspect an issue with the execution order of Swift top-level code, but I have not tracked down the root cause. For now I have left it in the form that works.

Second, the callback returns `Unmanaged.passRetained(event)`. When I changed it to `passUnretained`, the event tap stopped working.

### Handling lost CGEventTap events

The OS can disable a `CGEventTap` on its own: under heavy load, on timeout, or when the user changes some permission. Once disabled, key input is missed, so add logic to re-enable the event tap.

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap = self.tap {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return Unmanaged.passRetained(event)
}
```

If you handle this at the top of `handleEvent`, the tap recovers automatically even when the OS cuts it off. It is essential for a menu bar app that stays running for a long time.

#### Summary

> A modifier key pressed on its own arrives as `flagsChanged`. The bit flags in `event.flags.rawValue` are a reliable way to tell left from right. `CGEventTap` can be silently disabled, so add recovery for `.tapDisabledByTimeout` and `.tapDisabledByUserInput`.

## 3. CapsLock and `IOHIDManager`

As a second switching method, I added CapsLock: a single press for Eisuu (English), a double press for Japanese. Here I use `IOHIDManager` instead of `CGEventTap`.

The reason is that if the user has set the Caps Lock key's action to "No Action" in System Settings, no event reaches the `CGEventTap`. Many people remap CapsLock to Control or Escape or disable it, and it is not acceptable for switching to break in that case.

`IOHIDManager` reads input directly at the USB HID level. It works at a layer below the OS's "disable Caps Lock" setting, so it is not affected by System Settings.

An outline of the implementation:

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

    // Detect usagePage == 0x07 (Keyboard) and usage == 0x39 (CapsLock)
    // Distinguish single and double presses by the interval (0.3 s)
}, nil)

IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(),
                                CFRunLoopMode.commonModes.rawValue)
IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
```

Narrow it down to keyboard devices with `matchingDict`. Without this, `inputValueCallback` is also called for the mouse and trackpad, running unnecessary work.

### Permission request

Reading raw input with `IOHIDManager` requires the macOS `Input Monitoring` permission. The user grants it under `System Settings > Privacy & Security > Input Monitoring`. There is no built-in mechanism that shows a permission dialog on first launch, so it is a good idea for the app to offer a way to open the settings screen, for example from its menu.

#### Summary

> If you want to capture keyboard input regardless of System Settings, consider `IOHIDManager`, which sits below `CGEventTap`. It requires the `Input Monitoring` permission. Don't forget to narrow the matching dictionary to keyboard devices.

## 4. The `TISSelectInputSource` bug and the virtual-key workaround

This is the core of the article. So that anyone who lands here by searching for the same symptoms can reach the fix quickly, it goes in the order symptoms → isolation → workaround.

### Symptoms

- When a background agent switches to Japanese input with `TISSelectInputSource`, **the menu bar input indicator changes to "あ", but the actual input state stays ABC**
- Typing produces half-width Latin characters
- Calling it from a foreground app works correctly
- Even when called from the background, **switching to English works**
- Only switching to Japanese is broken, asymmetrically

This is the implementation the AI first suggested. As use of the official API, it is correct.

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

### Isolating the cause

I ruled out the hypotheses the AI first came back with, one by one.

1. **Accessibility/Input Monitoring permission not granted?** → Both were granted. Removing and re-adding them did not change the symptoms. Not the cause.
2. **Called too early?** → Delaying with `DispatchQueue.main.async` by a few hundred milliseconds to several seconds gave the same symptoms. Not the cause.
3. **Wrong input source ID?** → The same ID is recognized when switching manually. Not the cause.
4. **Focus on the asymmetry** → Switching to English works; only Japanese breaks. This asymmetry cannot be explained by how the API is used. An OS-side bug is likely.

At this point I concluded it matched a known macOS bug, [openradar #5021326444232704](https://openradar.appspot.com/radar?id=5021326444232704): a years-old defect where only switching to Japanese with `TISSelectInputSource` from the background fails.

### Workaround: sending virtual keys

JIS keyboards have physical "Eisuu" (keyCode 102) and "Kana" (keyCode 104) keys. When the OS receives these keys, it switches the input source. This path is handled at a layer below `TISSelectInputSource`, so the bug does not affect it.

US keyboards do not have these physical keys, but when a virtual "keyCode 102 was pressed" event arrives, the OS switches the input source regardless of whether the physical key exists. By synthesizing and posting this virtual event with `CGEvent`, you can bypass the bug.

Code you can reuse as is:

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

With this implementation, the menu bar indicator and the actual input state stay in sync even when called from the background.

### Side effects

The concern with sending virtual keys is whether it disturbs the state of other keys. Within what I tested, I confirmed the following:

- Modifier state (such as Shift being held) is not reset. Using `CGEventSource(stateID: .hidSystemState)` avoids polluting other apps' key input state
- Behavior may be unstable while waiting for dead key input. It is hard to tell from outside whether the IME is in the middle of dead key input, so I gave up on handling it completely
- Sending `keyCode 102/104` while another input source (Chinese, Korean, etc.) is active may cause unintended behavior. I accepted this on the premise that EnJaSwitcher is only for Eisuu/Kana switching

#### Summary

> When you find an asymmetric bug in an official OS API, think about substituting a layer one level below the API (here, virtual key events). AI can produce the general solution that follows the API documentation, but edge-case bugs can only be isolated by a human observing the symptoms.

## 5. Self-signed certificates, the TCC database, and persistent permissions

Because the app requires both `Accessibility` and `Input Monitoring`, having to reset permissions on every build would be painful. The practice that avoids this is the TCC workaround.

macOS's TCC (Transparency, Consent, and Control) database identifies apps by their **signing identity**. Binaries signed with the same identity are treated as "the same app", and permissions carry over. If the signature changes, TCC treats it as a different app and the permissions have to be granted again.

At first I built with ad-hoc signing (`codesign --sign -`). This signature produces a different identity on every build, so TCC treated each build as a different app, and I had to re-grant `Accessibility` and `Input Monitoring` every time. When that keeps happening during development, you cannot make progress.

The fix is to sign with a fixed self-signed certificate created in Keychain. For personal distribution without notarization, this is practical enough.

1. Keychain Access → Certificate Assistant → Create a Certificate
2. Name: `EnJaSwitcher Dev` (any name), Identity Type: Self-Signed Root, Certificate Type: Code Signing
3. After creating it, sign every build with this certificate

```bash
codesign --force --sign "EnJaSwitcher Dev" EnJaSwitcher.app
```

You can check the signature with `codesign`:

```bash
codesign -d --verbose=4 EnJaSwitcher.app
```

If `Authority=EnJaSwitcher Dev` appears, it is signed with the intended certificate.

If you ever recreate the certificate or accidentally build without signing, TCC treats it as a different app. In that case, remove the old entry from the permission list in `System Settings` with the minus button, then add the new `.app` with the plus button.

#### Summary

> TCC identifies apps by signing identity. Create a self-signed certificate once and sign every build with it, and you avoid the chore of re-granting permissions over and over during development.

## 6. LaunchAgents and the permission misattribution trap

Launching at login is done with a LaunchAgent. Since v1.3.0, turning on "Launch at Login (Background)" in the menu makes the app write `~/Library/LaunchAgents/com.local.enja-switcher.plist` itself and register it. This is the plist it writes (`ProgramArguments` holds the path of the binary inside the running `.app`):

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

### Don't set `KeepAlive`

With `KeepAlive = true`, `launchd` restarts the process every time it exits. That is handy for recovering from crashes, but when the user chooses Quit from the menu, the app comes right back up and can never be quit. A resident app that should be quittable from its menu should not set it.

### `ProcessType: Interactive`

Without it, `launchd` treats the job as a lightweight background task and throttles it, so the app may start tens of seconds to a minute after login instead of right away. This is an app the user interacts with directly, so specify `Interactive`.

### Registering and unregistering

On macOS 13 and later, placing the plist on disk is not enough for it to start at login. It has to be registered with `launchctl` so that it is added to macOS Background Item Management. The app runs the following only when the job is not registered yet:

```bash
launchctl load -w ~/Library/LaunchAgents/com.local.enja-switcher.plist
```

Checking the status:

```bash
launchctl list | grep enja-switcher
```

Registering has a side effect. Because `RunAtLoad` is `true`, `launchd` starts a new process the moment you `load`, so two instances end up running. To handle this, the app checks right after launch whether a process with the same bundle ID is already running, and the later one exits.

```swift
let myPID = ProcessInfo.processInfo.processIdentifier
let runningInstances = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.local.enja-switcher"
).filter { $0.processIdentifier != pid_t(myPID) }
if !runningInstances.isEmpty {
    exit(0)
}
```

Unregistering (turning the menu item off) only deletes the plist file. Calling `launchctl unload` sends SIGTERM when the app itself is running under `launchd`, which kills the running app. Once the file is gone, the app does not start at the next login, and because there is no `KeepAlive`, the registration left in memory does no harm.

### The trap: launching from Terminal misattributes permissions

Running the binary directly from Terminal during development will trip you up.

```bash
# Doing this grants Accessibility/Input Monitoring to Terminal.app
./EnJaSwitcher.app/Contents/MacOS/enja-switcher
```

macOS is designed to request permissions on behalf of the parent process, so a permission request from a process launched in Terminal is addressed to `Terminal.app`. As a result, `EnJaSwitcher.app` never gets the permissions, and it does not work in production (when launched via the LaunchAgent).

The correct way is to launch it with the `open` command.

```bash
open /Applications/EnJaSwitcher.app
```

With a LaunchAgent, `launchd` launches the binary directly, so the parent-process problem does not occur. The permissions are correctly granted to `EnJaSwitcher.app`.

#### Summary

> When running resident via a LaunchAgent, leave out `KeepAlive` and set `ProcessType: Interactive`. On macOS 13 and later the app does not start at login unless it is registered with `launchctl load -w`, but `RunAtLoad` then starts a second instance, so add duplicate-launch detection. Unregister by deleting the plist only. Running the binary directly from Terminal during development attaches the permissions to `Terminal.app`, so use the `open` command.

## Lessons from the whole project

What I felt most strongly in this project is that **a sense of the system's layer structure is what lets you get the most out of AI**.

How I found `IOHIDManager` and how I worked around the `TISSelectInputSource` bug by sending virtual keys followed the same pattern. Hunches like "there should be something in a layer below the OS's public API" or "this must be handled further down" determine the quality of the questions you ask the AI. If the question is right, the AI supplies the knowledge. If the question is vague, you get a plausible general answer, and you stop there.

You can leave knowledge of specific APIs to the AI. What you cannot leave to it is holding the overall map of which layers exist and where. The stronger your foundation in computer science, how operating systems work, and the structure of the I/O layers, the more you can draw out of the AI.

Even in an era where we have AI write code with us, the importance of fundamentals does not go down. If anything, I feel it goes up.

---

### Repository

- [EnJaSwitcher (GitHub)](https://github.com/toshi-kuji/enja-switcher)
- [Landing page](https://toshi-kuji.github.io/enja-switcher/en/)

### Related article

- [note: I released an app over the weekend. I didn't write a single line of code.](https://note.com/toshi_kuji/n/ne8c617810c5a) (in Japanese) - about the process and my view of the work behind the same project
