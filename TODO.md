# EnJaSwitcher GUI Application Plan

## Overview
Transform the current `enja-switcher` into a native macOS GUI application. The app currently runs as a background-only process using `CGEventTap` to intercept Command keys and simulate JIS Kana/Eisu keys. The goal is to add a menu bar resident (status bar) UI. Users will be able to click the menu bar icon to reveal a simple native menu where they can configure how they switch between English and Japanese input sources.

## Features
- **Menu Bar Resident:** Runs silently in the background, accessible only via the macOS menu bar (maintaining `LSUIElement` behavior).
- **Native Menu:** A simple, native dropdown menu using `AppKit` (`NSMenu`).
- **Switching Methods:**
  - **Option 1:** Left Command (English) / Right Command (Japanese) - *Current Behavior*
  - **Option 2:** CapsLock (Single press for English, Double press for Japanese - or toggle) - *New Feature*
- **Settings Persistence:** Remembers the user's chosen switching method across restarts.

## Icon Strategy
1. **SF Symbols (Recommended for Menu Bar Icon)**
   By utilizing Apple's built-in "SF Symbols," we can specify a system icon name (e.g., `textformat.alt` or `globe`) in the code. This automatically provides a beautiful, native icon in the menu bar that supports both Dark and Light modes without requiring any external image files.

2. **Automated Rendering (For Application `.icns`)**
   For the main application icon that appears in "System Settings" and "Activity Monitor" (e.g., a simple blue background with "A/あ" text), we can use Swift's CoreGraphics or a Python script to programmatically render the image and convert it into an `.icns` file during the build process.

## Implementation Steps

### Phase 1: Application Lifecycle & UI Setup
- [ ] Migrate `main.swift` to bootstrap a native AppKit app.
  - Create an `AppDelegate` conforming to `NSApplicationDelegate`.
  - Use `NSApplication.shared.delegate = delegate` and `NSApplication.shared.run()` to replace the raw `CFRunLoopRun()`.
- [ ] Ensure `Info.plist` continues to have `LSUIElement` set to `YES`.

### Phase 2: Menu Bar UI (NSStatusBar)
- [ ] In `AppDelegate.applicationDidFinishLaunching`, create an `NSStatusItem` using `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
- [ ] Create a Menu Bar Icon (e.g., a simple text icon "A/あ", an SF Symbol, or a custom 16x16 / 32x32@2x image) and assign it to the status item's button.
- [ ] Create an `NSMenu` to attach to the status item.

### Phase 3: Menu Items & User Interaction
- [ ] Add menu items for the switching options:
  - `Left/Right Command` (Checkable)
  - `CapsLock (Single/Double)` (Checkable)
- [ ] Add a visual checkmark (`NSControl.StateValue.on`) to the currently active option.
- [ ] Add standard menu items:
  - `Separator`
  - `Quit EnJaSwitcher`
- [ ] Implement action methods for when the user clicks a menu item to update the active method.

### Phase 4: Core Logic Integration & Refactoring
- [ ] Refactor the existing `CGEventTap` logic from `main.swift` into a dedicated class (e.g., `EventInterceptor`).
- [ ] Adapt the `eventMask` to also listen for CapsLock events if necessary.
- [ ] Implement the two distinct interception strategies:
  - **Command Key Strategy:** Existing logic (detect lone presses of Left/Right Command).
  - **CapsLock Strategy:** Detect single vs. double presses of CapsLock using a timer/timestamp comparison.
- [ ] Connect the UI selection to the interceptor so it dynamically changes its behavior when the user selects a different option.

### Phase 5: State Persistence
- [ ] Use `UserDefaults` to store the selected switching method.
- [ ] On app launch, read from `UserDefaults` to restore the previously selected method and update the UI checkmarks and interceptor state accordingly.

### Phase 6: Permissions Handling (Accessibility) Refinement
- [ ] Integrate the existing `promptInputMonitoringPermission()` and `CGEvent.tapCreate` retry loop gracefully into the `AppKit` lifecycle. Ensure the UI remains responsive while waiting for permissions.

### Phase 7: Assets & App Icon
- [ ] Create an Application Icon (`.icns` file) so the app has a proper icon in macOS "System Settings" (Privacy & Security) and "Activity Monitor".
- [ ] Update `Info.plist` to include `CFBundleIconFile` pointing to the `.icns` file.
- [ ] Ensure the `.icns` file is correctly copied into `EnJaSwitcher.app/Contents/Resources/` during the build process.

### Phase 8: Polish & Release
- [ ] Test the application across different scenarios (sleep/wake, fast typing, multiple displays).
- [ ] Update documentation (`README.md`) to reflect the new GUI, settings, and how to use the CapsLock feature.
