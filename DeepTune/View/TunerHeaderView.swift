import SwiftUI

/// The instrument and tuning selectors plus the microphone and settings buttons
/// shown at the top of every tab.
struct TunerHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    let instrument: Instrument
    let tuning: Tuning
    let isMicrophoneGranted: Bool
    let onInstrumentTap: () -> Void
    let onTuningTap: () -> Void
    let onMicrophoneTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        ZStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onInstrumentTap) {
                        CompactSelector(
                            icon: instrument.type.iconName,
                            title: instrument.name,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: onTuningTap) {
                        CompactSelector(
                            icon: "dial.medium.fill",
                            title: tuning.name,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onMicrophoneTap) {
                        Image(systemName: isMicrophoneGranted ? "mic.fill" : "mic.slash.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(isMicrophoneGranted ? AppTheme.success : AppTheme.danger)
                            .frame(width: 34, height: 34)
                            .background(circleBackground)
                    }

                    Button(action: onSettingsTap) {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(circleBackground)
                    }
                }
            }

            VStack(spacing: 1) {
                Text("DeepTune")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, 120)
        }
    }

    private var circleBackground: some View {
        Circle()
            .fill(AppTheme.surfaceSecondary)
            .overlay(
                Circle()
                    .stroke(AppTheme.stroke.opacity(colorScheme == .dark ? 0.95 : 0.85), lineWidth: 1)
            )
            .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(0.26) : Color.black.opacity(0.12)), radius: 5, x: 0, y: 2)
    }
}
