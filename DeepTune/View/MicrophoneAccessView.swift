import SwiftUI

/// Stands in for a tuner tab while microphone access is missing, so the screen
/// says why nothing happens instead of sitting empty. The header stays usable.
struct MicrophoneAccessView: View {
    let permission: MicrophonePermission
    let header: TunerHeaderView
    let onRequestAccess: () -> Void

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            VStack(spacing: 8) {
                header
                    .frame(height: 88)

                MicrophoneAccessCard(permission: permission, onRequestAccess: onRequestAccess)
                    .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

/// Explains microphone access and offers the one action that can change it:
/// the system prompt if the user was never asked, Settings once they said no.
struct MicrophoneAccessCard: View {
    @Environment(\.openURL) private var openURL

    let permission: MicrophonePermission
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: permission == .denied ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(permission == .denied ? AppTheme.danger : AppTheme.accent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(AppTheme.accentSoft))

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .multilineTextAlignment(.center)

            Button(buttonTitle, action: primaryAction)
                .buttonStyle(.primary)
        }
        .padding(24)
        .appCard()
    }

    private var title: LocalizedStringKey {
        permission == .denied ? "Microphone access is off" : "DeepTune needs your microphone"
    }

    private var message: LocalizedStringKey {
        permission == .denied
            ? "Turn on Microphone for DeepTune in Settings to start tuning."
            : "It listens to your instrument to find its pitch. Audio is processed on your device and never saved."
    }

    private var buttonTitle: LocalizedStringKey {
        permission == .denied ? "Open Settings" : "Allow Microphone"
    }

    private func primaryAction() {
        guard permission == .denied else {
            onRequestAccess()
            return
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

#Preview("Not asked") {
    MicrophoneAccessCard(permission: .undetermined, onRequestAccess: {})
        .padding()
        .background(AppTheme.backgroundTop)
}

#Preview("Denied") {
    MicrophoneAccessCard(permission: .denied, onRequestAccess: {})
        .padding()
        .background(AppTheme.backgroundTop)
}
