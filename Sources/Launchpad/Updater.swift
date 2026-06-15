import AppKit
import Combine
import Sparkle

/// Wraps Sparkle's standard updater for Launchpad's transient-overlay lifecycle.
///
/// Two constraints from this app shape the design:
///  1. Launchpad has no persistent menu bar (it is a full-screen overlay that hides
///     the menu bar), so the manual "check for updates" entry point lives in the
///     Settings panel — not in an app menu the user can never reach.
///  2. Launchpad dismisses itself on `resignActive`. While Sparkle is presenting any
///     of its own windows we must NOT auto-dismiss, or the update flow gets killed.
///     `isShowingUpdateUI` is the guard `AppDelegate` reads before closing.
///
/// Scheduled (background) checks use Sparkle's "gentle reminder" mode: instead of
/// popping a modal over the overlay, we just flip `updateAvailable` and let the user
/// open the full Sparkle UI from Settings when they choose.
final class UpdaterController: NSObject, ObservableObject {
    private var controller: SPUStandardUpdaterController!

    /// True once Sparkle is ready to perform a user-initiated check.
    @Published private(set) var canCheckForUpdates = false
    /// A scheduled check found a newer version; surface a gentle in-app badge.
    @Published private(set) var updateAvailable = false
    /// Sparkle is presenting its own UI; AppDelegate suppresses auto-dismiss while true.
    @Published private(set) var isShowingUpdateUI = false

    override init() {
        super.init()
        // `self` is a fully-initialised NSObject after super.init(), so it is valid to
        // hand it to Sparkle as both delegates here.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Bound to the Settings toggle. Persisted by Sparkle in user defaults.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// User-initiated check. Brings up Sparkle's full UI (progress / release notes /
    /// install). Marks the UI active first so the overlay does not dismiss underneath it.
    func checkForUpdates() {
        isShowingUpdateUI = true
        updateAvailable = false
        controller.updater.checkForUpdates()
    }
}

// Feed URL + EdDSA public key are read from Info.plist (SUFeedURL / SUPublicEDKey).
// No overrides needed today; conformance is kept for future feed customisation.
extension UpdaterController: SPUUpdaterDelegate {}

extension UpdaterController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Returning false prevents Sparkle from popping its own modal over the transient
    /// overlay; we badge instead and let the user open the UI from Settings.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            if handleShowingUpdate {
                // Sparkle will show its UI (user-initiated path).
                self.isShowingUpdateUI = true
            } else {
                // Gentle path: a scheduled check found an update but we declined the
                // modal. Surface the badge.
                self.updateAvailable = true
            }
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { self.isShowingUpdateUI = false }
    }
}
