import SwiftUI

struct AutoTunerView: View {
    let model: AutoTunerViewModel
    let header: TunerHeaderView

    var body: some View {
        GeometryReader { _ in
            ZStack {
                AppTheme.backgroundTop
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    header
                        .frame(height: 88)

                    VStack(spacing: 6) {
                        AutoMeterView(model: model)

                        HStack {
                            Spacer()
                            AutoProgressToggle(model: model)
                        }
                        .padding(.top, 2)

                        HeadstockView(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
    }
}

/// Everything on the Auto screen that changes with each audio frame. Kept in its
/// own view so a frame only invalidates this, not the headstock or the header.
private struct AutoMeterView: View {
    let model: AutoTunerViewModel

    var body: some View {
        VStack(spacing: 6) {
            AutoStrobeArea(
                centsDistance: model.autoCentsDistance,
                targetNote: model.targetNote,
                isTuningSuccessful: model.isTuningSuccessful,
                isSignalDetected: model.isTargetSignalDetected,
                hasPitchReference: model.hasPitchReference
            )

            HStack {
                Text("\(model.autoCentsDistance, format: .number.precision(.fractionLength(1))) cents")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(feedbackColor)

                Spacer()

                Text("Progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.top, 2)

            progressBar
                .opacity(model.isTargetSignalDetected || model.tuneProgressRatio > 0 ? 1.0 : 0.45)
        }
    }

    private var feedbackColor: Color {
        AppTheme.autoStrobeRampColor(
            centsDistance: model.autoCentsDistance,
            isSignalDetected: model.isTargetSignalDetected,
            visualRangeCents: 80.0
        )
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let ratio = CGFloat(max(0.0, min(1.0, model.tuneProgressRatio)))
            let fillWidth = max(CGFloat(6.0), proxy.size.width * ratio)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.stroke.opacity(0.35))
                Capsule()
                    .fill(feedbackColor)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 9)
    }
}

private struct AutoProgressToggle: View {
    @Bindable var model: AutoTunerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Auto")
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)
            Toggle("", isOn: $model.isAutoProgressEnabled)
                .labelsHidden()
                .tint(AppTheme.accent)
                .scaleEffect(0.84)
            Text(model.isAutoProgressEnabled ? "On" : "Off")
                .font(.caption.weight(.bold))
                .foregroundColor(model.isAutoProgressEnabled ? AppTheme.success : AppTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(AppTheme.surfaceSecondary.opacity(0.85))
                .overlay(Capsule().stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1))
        )
    }
}
