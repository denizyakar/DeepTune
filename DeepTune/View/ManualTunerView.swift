import SwiftUI

struct ManualTunerView: View {
    let model: ManualTunerViewModel
    let header: TunerHeaderView

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    header
                        .frame(height: 88)

                    ManualStrobeArea(
                        centsDistance: model.manualCentsDistance,
                        detectedNote: model.detectedNote,
                        isSignalDetected: model.isSignalDetected
                    )
                    .padding(16)
                    .appCard()

                    ManualInfoPanel(model: model)
                        .padding(16)
                        .appCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 104)
            }
        }
    }
}

private struct ManualInfoPanel: View {
    let model: ManualTunerViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(model.detectedNote?.name ?? "--")
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundColor(model.isSignalDetected ? AppTheme.textPrimary : AppTheme.textTertiary)

                Text(model.detectedNote.map { "\($0.octave)" } ?? "")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Text(nearestLabel)
            .font(.subheadline.weight(.medium))
            .foregroundColor(AppTheme.textSecondary)

            HStack(spacing: 10) {
                ManualRangeCard(
                    title: "Lowest",
                    value: model.manualLowestFrequency.map(Self.hertz) ?? "--"
                )
                ManualRangeCard(
                    title: "Highest",
                    value: model.manualHighestFrequency.map(Self.hertz) ?? "--"
                )
            }

            Text("Manual mode follows the note you play instead of the selected tuning string.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 8)
        }
    }

    private var nearestLabel: LocalizedStringKey {
        guard let note = model.detectedNote else { return "Play a note to detect frequency" }
        return "Nearest \(note.nearestFrequency, format: .number.precision(.fractionLength(2))) Hz"
    }

    private static func hertz(_ frequency: Float) -> String {
        String(localized: "\(frequency, format: .number.precision(.fractionLength(2))) Hz")
    }
}

private struct ManualRangeCard: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke.opacity(0.7), lineWidth: 1)
                )
        )
    }
}
