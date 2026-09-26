import SwiftUI

/// The tuning needle shared by Auto and Manual, so both read the same way:
/// one scale, one colour ramp, one motion. Smoothing happens in the view
/// models; this only draws the value it is given.
struct StrobeMeter: View {
    /// ±50 cents is the whole gap to the neighbouring note, and the same scale
    /// in both modes means a needle position always means the same deviation.
    static let visualRangeCents: Float = 50

    @Environment(\.colorScheme) private var colorScheme
    @State private var width: CGFloat = 0

    let centsDistance: Float
    let noteLabel: String?
    let isSignalDetected: Bool
    var showsNeedle = true

    private static let tickCount = 21

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<Self.tickCount, id: \.self) { index in
                    let distance = abs(index - Self.tickCount / 2)
                    Rectangle()
                        .fill(distance == 0 ? Color.clear : AppTheme.meterGrid.opacity(index.isMultiple(of: 2) ? 0.74 : 0.50))
                        .frame(width: distance == 0 ? 0 : 1.35, height: CGFloat(max(24, 82 - (distance * 5))))
                        .frame(maxWidth: .infinity)
                }
            }

            Rectangle()
                .fill(needleColor.opacity(0.92))
                .frame(width: 2.8, height: 96)

            if let noteLabel {
                Text(noteLabel)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(badgeTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(badgeFill)
                            .overlay(Capsule().stroke(AppTheme.meterGrid.opacity(0.55), lineWidth: 1.2))
                    )
                    .offset(y: -22)
            }

            if showsNeedle {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(needleColor)
                    .frame(width: 6.6, height: 70)
                    .offset(x: needleOffset)
                    // Readings arrive about every 85 ms; a spring retargets without
                    // losing speed, so the needle glides between them.
                    .animation(.smooth(duration: 0.15), value: centsDistance)
                    // A new note starts a new needle rather than gliding across
                    // centre, which would read as a moment in tune.
                    .id(noteLabel)
            }

            if !isSignalDetected {
                Text("NO SIGNAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.surfaceSecondary.opacity(0.9)))
                    .offset(y: 28)
            }
        }
        .frame(height: 94)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var needleColor: Color {
        AppTheme.autoStrobeRampColor(
            centsDistance: centsDistance,
            isSignalDetected: isSignalDetected,
            visualRangeCents: Self.visualRangeCents
        )
    }

    /// Full scale lands on the outermost tick, so each tick is 5 cents.
    private var needleOffset: CGFloat {
        let outermostTick = width / CGFloat(Self.tickCount) * CGFloat(Self.tickCount / 2)
        let normalized = CGFloat(max(-1, min(1, centsDistance / Self.visualRangeCents)))
        return normalized * outermostTick
    }

    private var badgeFill: Color {
        colorScheme == .dark ? AppTheme.surfaceSecondary.opacity(0.22) : AppTheme.accent.opacity(0.42)
    }

    private var badgeTextColor: Color {
        colorScheme == .dark ? .white : AppTheme.textPrimary
    }
}

#Preview {
    VStack(spacing: 24) {
        StrobeMeter(centsDistance: 0, noteLabel: "E2", isSignalDetected: true)
        StrobeMeter(centsDistance: -18, noteLabel: "A2", isSignalDetected: true)
        StrobeMeter(centsDistance: 50, noteLabel: nil, isSignalDetected: false, showsNeedle: false)
    }
    .padding()
    .background(AppTheme.backgroundTop)
}
