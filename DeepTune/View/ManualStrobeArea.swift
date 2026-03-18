import SwiftUI

struct ManualStrobeArea: View {
    @Environment(\.colorScheme) private var colorScheme

    let centsDistance: Float
    let detectedNote: DetectedNote?
    let isSignalDetected: Bool

    private let maxVisualOffset: CGFloat = 122.0
    private let visualRangeCents: Float = 50.0

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

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.meterBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.stroke.opacity(0.55), lineWidth: 1)
                    )
                    .frame(height: 126)

                HStack(spacing: 0) {
                    ForEach(0..<21, id: \.self) { index in
                        let distance = abs(index - 10)
                        Rectangle()
                            .fill(index == 10 ? Color.clear : AppTheme.meterGrid.opacity(index.isMultiple(of: 2) ? 0.74 : 0.50))
                            .frame(width: index == 10 ? 0 : 1.35, height: CGFloat(max(30, 92 - (distance * 5))))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 0)

                Rectangle()
                    .fill(feedbackColor.opacity(0.95))
                    .frame(width: 2.8, height: 126)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(feedbackColor)
                    .frame(width: 6.2, height: 92)
                    .offset(x: clampedOffset)
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.76), value: centsDistance)

                noteBadge

                if !isSignalDetected {
                    Text("NO SIGNAL")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.surfaceSecondary.opacity(0.9)))
                        .offset(y: 42)
                }
            }

            HStack {
                Text(String(format: "%.1f cents", centsDistance))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(feedbackColor)

                Spacer()

                if let detectedNote {
                    Text(String(format: "Nearest %.2f Hz", detectedNote.nearestFrequency))
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

    private var noteBadge: some View {
        Group {
            if let detectedNote {
                Text("\(detectedNote.name)\(detectedNote.octave)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(noteBadgeTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AppTheme.surfaceSecondary.opacity(0.26))
                            .overlay(Capsule().stroke(AppTheme.meterGrid.opacity(0.35), lineWidth: 1))
                    )
                    .offset(y: -34)
            } else {
                Text("--")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .offset(y: -34)
            }
        }
    }

    private var noteBadgeTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var clampedOffset: CGFloat {
        let normalized = CGFloat(centsDistance / visualRangeCents)
        return max(-maxVisualOffset, min(maxVisualOffset, normalized * maxVisualOffset))
    }
}
