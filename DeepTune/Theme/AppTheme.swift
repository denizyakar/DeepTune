import SwiftUI

enum AppTheme {
    static let backgroundTop = Color("DTBackgroundTop")
    static let backgroundBottom = Color("DTBackgroundBottom")
    static let surfacePrimary = Color("DTSurfacePrimary")
    static let surfaceSecondary = Color("DTSurfaceSecondary")
    static let surfaceElevated = Color("DTSurfaceElevated")
    static let stroke = Color("DTStroke")

    static let textPrimary = Color("DTTextPrimary")
    static let textSecondary = Color("DTTextSecondary")
    static let textTertiary = Color("DTTextTertiary")

    static let accent = Color("DTAccent")
    static let accentSoft = Color("DTAccentSoft")

    static let success = Color("DTSuccess")
    static let warning = Color("DTWarning")
    static let danger = Color("DTDanger")

    static let meterBackground = Color("DTMeterBackground")
    static let meterGrid = Color("DTMeterGrid")

    static let headstockBase = Color("DTHeadstockBase")
    static let headstockOverlay = Color("DTHeadstockOverlay")

    static func feedbackColor(centsDistance: Float, isSignalDetected: Bool, isTuningSuccessful: Bool) -> Color {
        guard isSignalDetected else { return textTertiary }
        if isTuningSuccessful { return success }
        return centsDistance >= 0 ? danger : warning
    }

    static func feedbackLabel(centsDistance: Float, isSignalDetected: Bool, isTuningSuccessful: Bool) -> String {
        guard isSignalDetected else { return "No Signal" }
        if isTuningSuccessful { return "In Tune" }
        return centsDistance >= 0 ? "Sharp" : "Flat"
    }

    // Maps pitch distance to a continuous red->green spectrum.
    // |distance| near 0 cents = green, far from center = red.
    static func autoStrobeRampColor(centsDistance: Float, isSignalDetected: Bool, visualRangeCents: Float = 50.0) -> Color {
        guard isSignalDetected else { return textTertiary }

        let normalized = max(0.0, min(1.0, abs(centsDistance) / visualRangeCents))
        let hue = 0.33 * Double(1.0 - normalized) // 0.33 ~ green, 0.0 ~ red
        let saturation = 0.78 + (0.16 * Double(normalized))
        let brightness = 0.93

        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

struct AppCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(AppCardStyle(cornerRadius: cornerRadius))
    }
}
