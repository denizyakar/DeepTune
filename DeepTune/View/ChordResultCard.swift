import SwiftUI

/// The detected chord with its confidence and runner-up suggestions. Shared
/// so onboarding shows the real card with a sample result.
struct ChordResultCard: View {
    let result: ChordFinderViewModel.ChordMatch?

    private struct SuggestionDisplayRow: Identifiable {
        // Stable across renders so ForEach keeps its rows. Titles are unique because
        // candidates are de-duplicated by name before rows are built.
        var id: String { title }
        let title: String
        let rootLine: String
        let confidence: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Chord")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)

            if let lastResult = result {
                Text(lastResult.name)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Text("Confidence: \(Int((lastResult.confidence * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)

                Text(primaryRootLine(for: lastResult))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)

                Text("Observed notes: \(lastResult.observedNoteNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)

                if !lastResult.candidates.isEmpty {
                    Divider()
                        .overlay(AppTheme.stroke.opacity(0.45))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Top Suggestions")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textTertiary)

                        let rows = suggestionDisplayRows(for: lastResult)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(index + 1). \(row.title)")
                                    .font(.subheadline.weight(index == 0 ? .bold : .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer(minLength: 8)
                                Text("\(Int((row.confidence * 100).rounded()))%")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            Text(row.rootLine)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
            } else {
                Text("--")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)

                Text("No chord analyzed yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private func primaryRootLine(for result: ChordFinderViewModel.ChordMatch) -> String {
        if let bass = result.bassNoteName {
            return String(localized: "Root: \(result.rootName) • Lowest note: \(bass)")
        }
        return String(localized: "Root: \(result.rootName)")
    }

    private func uniqueCandidates(for result: ChordFinderViewModel.ChordMatch) -> [ChordFinderViewModel.ChordSuggestion] {
        var unique: [ChordFinderViewModel.ChordSuggestion] = []
        for candidate in result.candidates {
            if unique.contains(where: { $0.name == candidate.name }) {
                continue
            }
            unique.append(candidate)
        }
        return unique
    }

    private func suggestionDisplayRows(for result: ChordFinderViewModel.ChordMatch) -> [SuggestionDisplayRow] {
        let candidates = Array(uniqueCandidates(for: result).prefix(5))
        guard !candidates.isEmpty else { return [] }

        var rows: [SuggestionDisplayRow] = []
        var index = 0
        while index < candidates.count {
            let current = candidates[index]
            if index + 1 < candidates.count {
                let next = candidates[index + 1]
                if shouldMergeAsOr(current: current, next: next) {
                    rows.append(
                        SuggestionDisplayRow(
                            title: String(localized: "\(current.name) or \(next.name)"),
                            rootLine: String(localized: "Root: \(current.rootName) or \(next.rootName)"),
                            confidence: max(current.confidence, next.confidence)
                        )
                    )
                    index += 2
                    continue
                }
            }

            rows.append(
                SuggestionDisplayRow(
                    title: current.name,
                    rootLine: String(localized: "Root: \(current.rootName)"),
                    confidence: current.confidence
                )
            )
            index += 1
        }

        return rows
    }

    private func shouldMergeAsOr(
        current: ChordFinderViewModel.ChordSuggestion,
        next: ChordFinderViewModel.ChordSuggestion
    ) -> Bool {
        guard current.rootName != next.rootName else { return false }
        let confidenceGap = abs(current.confidence - next.confidence)
        return confidenceGap <= 0.04
    }
}
