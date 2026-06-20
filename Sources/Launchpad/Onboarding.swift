import SwiftUI

/// First-run welcome / permissions dialog. Shown once (tracked by
/// `AppSettings.onboardingShown`). Explains what the app does and offers a shortcut
/// to System Settings → Privacy so images in protected folders (Desktop/Documents)
/// can be used for wallpaper / slideshow backgrounds.
struct OnboardingView: View {
    @EnvironmentObject var store: LaunchpadStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text(store.t(.onboardingTitle))
                        .font(.system(size: 24, weight: .bold))
                }

                Text(store.t(.onboardingBody))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Label("\(store.catalogueCount)", systemImage: "app.badge.checkmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                HStack {
                    Button(store.t(.openPrivacy)) { store.openPrivacySettings() }
                    Spacer()
                    Button(store.t(.continueButton)) { store.dismissOnboarding() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .padding(40)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}
