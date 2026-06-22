import AppKit
import Combine
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
    let updater = UpdaterController()
    private var window: KeyableWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var videoBackgroundView: PlayerContainerView?
    private var settingsCancellable: AnyCancellable?
    private var videoActivity: NSObjectProtocol?

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

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]

        let videoBackground = PlayerContainerView(frame: container.bounds)
        videoBackground.autoresizingMask = [.width, .height]
        videoBackground.isHidden = true
        container.addSubview(videoBackground)

        let root = LaunchpadView(videoHandledExternally: true)
            .environmentObject(store)
            .environmentObject(updater)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        win.contentView = container

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
        self.videoBackgroundView = videoBackground
        settingsCancellable = store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.updateExternalVideoBackground(settings)
            }
        updateExternalVideoBackground(store.settings)

        installEventMonitors()
    }

    private func updateExternalVideoBackground(_ settings: AppSettings) {
        guard let videoBackgroundView else { return }
        guard settings.backgroundKind == .video else {
            videoBackgroundView.isHidden = true
            videoBackgroundView.teardown()
            setVideoActivity(false)
            return
        }

        let paths: [String]
        let random: Bool
        if let folder = settings.videoFolder {
            paths = videoFiles(in: folder)
            random = settings.videoRandom
        } else if let path = settings.videoPath {
            paths = [(path as NSString).expandingTildeInPath]
            random = false
        } else {
            paths = []
            random = false
        }

        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else {
            videoBackgroundView.isHidden = true
            videoBackgroundView.teardown()
            setVideoActivity(false)
            return
        }

        videoBackgroundView.isHidden = false
        videoBackgroundView.configure(
            paths: existing,
            random: random,
            muted: settings.videoMuted,
            volume: settings.videoVolume
        )
        setVideoActivity(true)
    }

    private func setVideoActivity(_ active: Bool) {
        if active {
            guard videoActivity == nil else { return }
            videoActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Playing Launchpad video background"
            )
        } else if let activity = videoActivity {
            ProcessInfo.processInfo.endActivity(activity)
            videoActivity = nil
        }
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
        // Don't dismiss while Sparkle is presenting its own update window, or the
        // overlay would close underneath it and kill the update flow.
        guard !updater.isShowingUpdateUI else { return }
        // Keep the overlay alive while the first-run onboarding is up — otherwise
        // tapping "Open Privacy Settings" (which activates System Settings) would
        // terminate us mid-onboarding.
        guard !store.showOnboarding else { return }
        store.requestClose()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        videoBackgroundView?.teardown()
        setVideoActivity(false)
    }
}
