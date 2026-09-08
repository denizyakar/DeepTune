import SwiftUI

struct ChordFinderView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Binding var isSessionActive: Bool

    @State private var model: ChordFinderViewModel
    @State private var listeningLoopTask: Task<Void, Never>?

    init(viewModel: TunerViewModel, isSessionActive: Binding<Bool>) {
        self.viewModel = viewModel
        self._isSessionActive = isSessionActive
        self._model = State(initialValue: ChordFinderViewModel(audioSource: viewModel))
    }

    private struct SuggestionDisplayRow: Identifiable {
        let id = UUID()
        let title: String
        let rootLine: String
        let confidence: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chord Finder")
                .font(.title3.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)

            Text("Tap Start, play one chord once, then wait.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)

            HStack(spacing: 10) {
                Button(action: toggleSession) {
                    Text(isSessionActive ? "Stop" : "Start")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSessionActive ? AppTheme.danger : AppTheme.accent)
                        )
                        .foregroundColor(.white)
                }

                statusBadge
            }

            if model.phase == .capturing {
                Text("Captured: \(model.samples.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if model.phase == .ready {
                Text("Ready: play one chord now")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if model.phase == .analyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("WAIT - analyzing...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.top, 2)
            }

            resultCard

            Text("Tip: For best accuracy, let the chord ring for a short moment and avoid changing chords while WAIT is visible.")
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary)

            switch model.modelStatus {
            case .loading:
                Text("Preparing chord model...")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textTertiary)
            case .unavailable:
                Text("ML model not found in bundle (nmp.mlpackage/mlmodelc). Running fallback detector.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.warning)
            case .ready:
                EmptyView()
            }
        }
        // Loading the CoreML model takes a noticeable moment; keep it off the main
        // actor so switching to this tab does not stall the UI.
        .task {
            model.onRequestSessionEnd = { isSessionActive = false }
            await model.prepareModel()
        }
        .onChange(of: isSessionActive) { _, isActive in
            if isActive {
                model.beginListening()
                startListeningLoop()
            } else {
                stopListeningLoop()
                model.stopListening()
            }
        }
        .onDisappear {
            isSessionActive = false
            stopListeningLoop()
            model.stopListening()
        }
    }

    private func startListeningLoop() {
        listeningLoopTask?.cancel()
        listeningLoopTask = Task { await model.runListeningLoop() }
    }

    private func stopListeningLoop() {
        listeningLoopTask?.cancel()
        listeningLoopTask = nil
    }

    private var statusBadge: some View {
        let label: String
        let color: Color

        switch model.phase {
        case .idle:
            label = "Idle"
            color = AppTheme.textTertiary
        case .ready:
            label = "Ready"
            color = AppTheme.success
        case .capturing:
            label = "Listening"
            color = AppTheme.accent
        case .analyzing:
            label = "WAIT"
            color = AppTheme.warning
        }

        return Text(label)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceSecondary)
                    .overlay(
                        Capsule().stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1)
                    )
            )
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Chord")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)

            if let lastResult = model.lastResult {
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

    private func toggleSession() {
        if isSessionActive {
            isSessionActive = false
        } else {
            model.clearLastResult()
            isSessionActive = true
        }
    }

    private func primaryRootLine(for result: ChordFinderViewModel.ChordMatch) -> String {
        if let bass = result.bassNoteName {
            return "Root: \(result.rootName) • Lowest note: \(bass)"
        }
        return "Root: \(result.rootName)"
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
                            title: "\(current.name) or \(next.name)",
                            rootLine: "Root: \(current.rootName) or \(next.rootName)",
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
                    rootLine: "Root: \(current.rootName)",
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
