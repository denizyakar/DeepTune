import SwiftUI

struct AutoStrobeArea: View {
    @Environment(\.colorScheme) private var colorScheme

    let centsDistance: Float
    let targetNote: Note?
    let isTuningSuccessful: Bool
    let isSignalDetected: Bool
    let hasPitchReference: Bool

    private let maxVisualOffset: CGFloat = 152.0
    private let visualRangeCents: Float = 50.0

    private var feedbackColor: Color {
        AppTheme.autoStrobeRampColor(
            centsDistance: centsDistance,
            isSignalDetected: isSignalDetected,
            visualRangeCents: visualRangeCents
        )
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<21, id: \.self) { index in
                    let distance = abs(index - 10)
                    Rectangle()
                        .fill(index == 10 ? Color.clear : AppTheme.meterGrid.opacity(index.isMultiple(of: 2) ? 0.74 : 0.50))
                        .frame(width: index == 10 ? 0 : 1.35, height: CGFloat(max(24, 82 - (distance * 5))))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 0)

            Rectangle()
                .fill(feedbackColor.opacity(0.92))
                .frame(width: 2.8, height: 96)

            if let targetNote {
                Text("\(targetNote.name)\(targetNote.octave)")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundColor(targetTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(targetBadgeFill)
                            .overlay(Capsule().stroke(AppTheme.meterGrid.opacity(0.55), lineWidth: 1.2))
                    )
                    .offset(y: -22)
            }

            if hasPitchReference {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(feedbackColor)
                    .frame(width: 6.6, height: 70)
                    .offset(x: clampedOffset)
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.76), value: centsDistance)
            }

            if !isSignalDetected {
                Text("NO SIGNAL")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.surfaceSecondary.opacity(0.9)))
                    .offset(y: 28)
            }
        }
        .frame(height: 94)
    }

    private var targetBadgeFill: Color {
        colorScheme == .dark ? AppTheme.surfaceSecondary.opacity(0.22) : AppTheme.accent.opacity(0.42)
    }

    private var targetTextColor: Color {
        colorScheme == .dark ? .white : AppTheme.textPrimary
    }

    private var clampedOffset: CGFloat {
        let normalized = CGFloat(centsDistance / visualRangeCents)
        return max(-maxVisualOffset, min(maxVisualOffset, normalized * maxVisualOffset))
    }
}
