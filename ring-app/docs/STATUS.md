# Ring App - Status & Known Issues

## Current State
The app builds and runs. The menubar popover (NSStatusItem + NSPopover) works correctly — you can see providers, expand rows, click buttons within the popover itself.

## The Bug: Interactive controls don't work in secondary views

When opening any secondary view (SetupWizard, Scopes, CredentialAdd) from the menubar popover, **Toggle checkboxes, List row interactions, and some buttons don't respond to mouse clicks**. Simple buttons like "Cancel" or "Done" sometimes work, but Toggles and List-based interactions never do.

This affects:
- **SetupWizardView** Step 4: scope selection with Toggle(.checkbox) — can't check/uncheck
- **ScopesView**: List rows with buttons — can't click "add scope" buttons
- **ConnectView** (deleted): had same issue

## Approaches Tried (all failed)

### 1. `.sheet()` from popover
The standard SwiftUI approach. Sheets open visually but interactive controls inside them don't receive mouse events. This is a known macOS bug with sheets presented from NSPopover.

### 2. Separate NSWindow (manual creation)
Created an NSWindow manually with NSHostingController, called `makeKeyAndOrderFront`. The window appears but interactive controls still don't work. Tried variations:
- Setting window level
- Calling `NSApp.activate(ignoringOtherApps: true)`
- Keeping strong reference to window via static var

### 3. Close popover before opening window
Closed the popover first, then opened the NSWindow. Same result — controls don't respond.

### 4. Notification-driven sheet
Used NotificationCenter to trigger a `.sheet(item:)` on MenuBarView after the wizard dismissed. The sheet opened but had the same interactivity issues.

### 5. Integrated into wizard (no separate view)
Moved scope selection into SetupWizardView as Step 4, so it uses the same sheet that already works for text fields and buttons. Text fields and buttons in steps 1-3 work, but Toggle checkboxes in step 4 still don't respond.

### 6. WindowManager singleton with standalone NSWindow
Created a WindowManager that opens views in completely standalone NSWindows (not sheets). Uses `NSWindow(contentRect:styleMask:backing:defer:)` with `.titled, .closable` style. Window appears but same issue with interactive controls.

## Architecture

- **App.swift**: `AppDelegate` manages `NSStatusItem` + `NSPopover` (behavior: `.applicationDefined`)
- **MenuBarView.swift**: Main popover content. Currently calls `WindowManager.shared.open()` to open secondary views
- **SetupWizardView.swift**: Multi-step wizard (1: dashboard, 2: redirect/apikey, 3: credentials, 4: scopes+connect). Step 4 has Toggle checkboxes for scope selection
- **ScopesView.swift**: Shows scope list for already-connected providers with add buttons
- **WindowManager.swift**: Singleton that opens SwiftUI views in standalone NSWindows

## Key Files
- `Sources/App.swift` — AppDelegate with NSStatusItem + NSPopover
- `Sources/WindowManager.swift` — NSWindow opener (latest attempt)
- `Sources/Views/MenuBarView.swift` — Popover content, calls WindowManager
- `Sources/Views/SetupWizardView.swift` — Setup wizard with integrated scope selection
- `Sources/Views/ScopesView.swift` — Scope management view
- `Sources/Models/Provider.swift` — All 13 providers with scope definitions
- `Sources/KeychainStore.swift` — Keychain access, @MainActor ObservableObject
- `Sources/OAuth/OAuthFlow.swift` — OAuth2 flows (ASWebAuthenticationSession + localhost callback)
- `Sources/OAuth/LocalCallbackServer.swift` — NWListener on port 9876 for Google

## What Works
- Menubar popover opens/closes correctly
- Provider rows expand/collapse
- Buttons in the popover (Scopes, Login, Logout, Remove, Refresh, Quit) all work
- Text fields in SetupWizardView steps 1-3 work when opened as sheet
- The Go CLI (`ring login`, `ring token`, etc.) works perfectly

## What Doesn't Work
- Toggle(.checkbox) in any view opened from the popover
- List row tap interactions
- This happens regardless of whether the view is presented as .sheet(), NSWindow, or NSPanel

## Theories Not Yet Tested
- **Use NSPanel instead of NSWindow** with `.nonactivatingPanel` or `.utilityWindow` style mask — panels have different event handling
- **Use a regular NSWindow for the menubar dropdown** instead of NSPopover entirely — avoid the popover event chain altogether
- **Use NSViewController presentation** (`presentAsSheet`, `presentAsModalWindow`) instead of SwiftUI `.sheet()`
- **Add explicit `.focusable()` or `.allowsHitTesting(true)`** to Toggle views
- **Try `MenuBarExtra` with `.window` style** (macOS 14+) instead of manual NSStatusItem — Apple's implementation may handle event routing correctly
- **Use `openWindow` environment action** with a WindowGroup scene instead of manual NSWindow creation
- **Debug with Accessibility Inspector** to see if the Toggle elements are actually in the view hierarchy and receiving accessibility events

## Build & Run
```bash
cd /Users/jordi/projects/ring/ring-app
xcodegen generate
xcodebuild -scheme Ring -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
open ~/Library/Developer/Xcode/DerivedData/Ring-gvqrmooyftlhrkaseqhilqmblyjp/Build/Products/Debug/Ring.app
```
