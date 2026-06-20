import SwiftUI

/// Centralised animation policy so every view honours the user's
/// "enable animations" toggle and global speed multiplier.
extension AppSettings {
    /// An ease-in-out animation scaled by the speed multiplier, or `nil` (instant)
    /// when animations are disabled. `base` is the default duration in seconds.
    func anim(_ base: Double = 0.2) -> Animation? {
        guard animationsEnabled else { return nil }
        return .easeInOut(duration: base / max(0.1, animationSpeed))
    }

    /// Spring variant (used for page settle), or nil when disabled.
    func spring(_ response: Double = 0.35) -> Animation? {
        guard animationsEnabled else { return nil }
        return .spring(response: response / max(0.1, animationSpeed), dampingFraction: 0.85)
    }

    /// Duration used for the open/close overlay transition (speed-scaled).
    var openCloseDuration: Double { animationsEnabled ? 0.24 / max(0.1, animationSpeed) : 0 }

    /// Animation for the open/close transition, or nil (instant) when disabled or
    /// when the user picked the `.none` open style.
    var openAnim: Animation? {
        guard animationsEnabled, openAnimation != .none else { return nil }
        return .easeOut(duration: 0.24 / max(0.1, animationSpeed))
    }
}

/// Applies the chosen open/close transition (zoom / fade / slide / none) to the
/// foreground Launchpad content based on the `presented` flag.
struct OpenTransition: ViewModifier {
    let style: OpenAnimation
    let presented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(presented ? 1 : 0)
            .scaleEffect(scale, anchor: .center)
            .offset(y: yOffset)
    }

    private var scale: CGFloat {
        style == .zoom ? (presented ? 1 : 0.92) : 1
    }
    private var yOffset: CGFloat {
        style == .slide ? (presented ? 0 : 48) : 0
    }
}
