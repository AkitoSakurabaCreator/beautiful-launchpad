import AppKit
import SwiftUI

/// Borderless windows cannot become key by default; allow it so the search field
/// and keyboard shortcuts work.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
enum LaunchpadMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LaunchpadStore()
    private var window: KeyableWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        store.onDismiss = { NSApp.terminate(nil) }
        store.loadAndScan()

        // Open on whichever display currently has the mouse cursor, so triggering
        // it on a second monitor opens it there (not always on the primary screen).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let win = KeyableWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .normal
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isMovableByWindowBackground = false
        win.setFrame(frame, display: true)

        let root = LaunchpadView().environmentObject(store)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        installEventMonitors()
    }

    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 43 where event.modifierFlags.contains(.command): // ⌘,
                self.store.showSettings.toggle()
                return nil
            case 53: // esc
                self.store.escape()
                return nil
            case 123: // left arrow
                self.store.prevPage()
                return nil
            case 124: // right arrow
                self.store.nextPage()
                return nil
            case 36, 76: // return / enter
                if self.store.isSearching {
                    self.store.launchFirstResult()
                    return nil
                }
                return event
            default:
                return event
            }
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            self.store.handleScrollEvent(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                phase: event.phase,
                momentum: event.momentumPhase,
                precise: event.hasPreciseScrollingDeltas
            )
            return event
        }
    }

    /// Become a true full-screen overlay: hide the menu bar and Dock while the
    /// Launchpad is up so nothing peeks through at the top/edges of the screen.
    /// They are restored automatically when the app stops being frontmost or
    /// terminates. Set here (rather than in didFinishLaunching) because
    /// `presentationOptions` may only be changed while the app is active, which
    /// this callback guarantees. The window stays at `.normal` level so the
    /// export/import/colour panels still appear above it.
    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }

    /// Classic Launchpad dismisses itself the moment it is no longer frontmost
    /// (Cmd-Tab, clicking another app or the desktop). In-app modal panels
    /// (save/open/colour pickers) keep the app active, so they do not trigger this;
    /// the `modalWindow` guard is belt-and-suspenders for any modal edge case.
    func applicationDidResignActive(_ notification: Notification) {
        guard NSApp.modalWindow == nil else { return }
        store.requestClose()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
