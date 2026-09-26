import SwiftUI

/// The pill-shaped selector used in the tuner header.
struct CompactSelector: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppTheme.accentSoft))

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isInteractive {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke.opacity(colorScheme == .dark ? 0.95 : 0.85), lineWidth: 1)
                )
                .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(0.20) : Color.black.opacity(0.10)), radius: 4, x: 0, y: 2)
        )
        .frame(width: 134, alignment: .leading)
    }
}
