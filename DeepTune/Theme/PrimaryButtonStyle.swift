import SwiftUI

/// The app's filled call-to-action button. Defined once so a theme change
/// reaches every screen that uses it, onboarding included.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }

    static func primary(tint: Color) -> PrimaryButtonStyle {
        PrimaryButtonStyle(tint: tint)
    }
}
