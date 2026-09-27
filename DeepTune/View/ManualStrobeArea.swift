import SwiftUI

struct ManualStrobeArea: View {
    let centsDistance: Float
    let detectedNote: DetectedNote?
    let isSignalDetected: Bool

    private var isWithinTuneWindow: Bool {
        abs(centsDistance) <= 7.0
    }

    private var feedbackColor: Color {
        AppTheme.feedbackColor(
            centsDistance: centsDistance,
            isSignalDetected: isSignalDetected,
            isTuningSuccessful: isWithinTuneWindow
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manual Strobe")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Text(AppTheme.feedbackLabel(
                    centsDistance: centsDistance,
                    isSignalDetected: isSignalDetected,
                    isTuningSuccessful: isWithinTuneWindow
                ))
                .font(.caption.weight(.semibold))
                .foregroundColor(feedbackColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(feedbackColor.opacity(0.16)))
            }

            StrobeMeter(
                centsDistance: centsDistance,
                noteLabel: detectedNote.map { "\($0.name)\($0.octave)" },
                isSignalDetected: isSignalDetected
            )
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.meterBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.stroke.opacity(0.55), lineWidth: 1)
                    )
            )

            HStack {
                Text("\(centsDistance, format: .number.precision(.fractionLength(1))) cents")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(feedbackColor)

                Spacer()

                if let detectedNote {
                    Text("Nearest \(detectedNote.nearestFrequency, format: .number.precision(.fractionLength(2))) Hz")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text("Play a note to start")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }
}
