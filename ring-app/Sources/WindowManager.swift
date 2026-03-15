import AppKit
import SwiftUI

/// Opens SwiftUI views in standalone NSWindows (not sheets from a popover).
/// This avoids the macOS bug where sheets presented from NSPopover don't receive mouse events.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

    func open<Content: View>(
        id: String,
        title: String,
        size: NSSize,
        content: @escaping () -> Content
    ) {
        // Close existing window with same id
        close(id: id)

        let hostingController = NSHostingController(rootView: content())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowCleanup(manager: self, id: id)
        windows[id] = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }
}

private class WindowCleanup: NSObject, NSWindowDelegate {
    let manager: WindowManager
    let id: String

    init(manager: WindowManager, id: String) {
        self.manager = manager
        self.id = id
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.manager.close(id: self.id)
        }
    }
}
