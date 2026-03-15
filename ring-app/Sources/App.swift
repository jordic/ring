import SwiftUI
import AppKit

@main
struct RingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Menubar-only app: l'status item es gestiona des de l'AppDelegate.
        // Cal almenys una Scene per compilar.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = KeychainStore()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "ring")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover amb behavior .applicationDefined = NO es tanca sol
        let contentView = MenuBarView()
            .environmentObject(store)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 460, height: 640)
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            installEscapeMonitor()
        }
    }

    func closePopover() {
        popover?.close()
        removeEscapeMonitor()
    }

    // Escape tanca el popover
    private func installEscapeMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
