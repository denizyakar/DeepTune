import SwiftUI

struct ChordFinderView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Binding var isSessionActive: Bool

    private let basicPitchAnalyzer = BasicPitchChordAnalyzer.shared

    private enum ModelStatus {
        case loading
        case ready
        case unavailable
    }

    private enum Phase {
        case idle
        case ready
        case capturing
        case analyzing
    }

    struct NoteSample: Identifiable {
        let id = UUID()
        let pitchClass: Int
        let midiNumber: Int
        let timestamp: Date
    }

    struct ChordMatch {
        let name: String
        let rootName: String
        let confidence: Double
        let observedNoteNames: [String]
        let bassNoteName: String?
        let candidates: [ChordSuggestion]
    }

    struct ChordSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let rootName: String
        let confidence: Double
    }

    private struct SuggestionDisplayRow: Identifiable {
        let id = UUID()
        let title: String
        let rootLine: String
        let confidence: Double
    }

    @State private var phase: Phase = .idle
    @State private var samples: [NoteSample] = []
    @State private var lastResult: ChordMatch?
    @State private var lastAcceptedMIDI: Int?
    @State private var lastAcceptedAt: Date?
    @State private var captureStartedAt: Date?
    @State private var lastStrongSignalAt: Date?
    @State private var analysisTask: Task<Void, Never>?
    @State private var listeningLoopTask: Task<Void, Never>?
    @State private var strongSignalStreak = 0
    @State private var sawQuietFrameInReady = false
    @State private var modelStatus: ModelStatus = .loading

    private let listeningPollIntervalNanoseconds: UInt64 = 120_000_000
    private let repeatedMIDICooldown: TimeInterval = 0.08
    private let captureStartAmplitudeThreshold: Float = 0.020
    private let captureSustainAmplitudeThreshold: Float = 0.011
    private let onsetRequiredFrames = 2
    private let minimumCaptureDuration: TimeInterval = 0.45
    private let releaseSilenceBeforeAnalyze: TimeInterval = 0.32
    private let maximumCaptureDuration: TimeInterval = 2.20
    private let minimumSamplesForAnalysis = 5

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

            if phase == .capturing {
                Text("Captured: \(samples.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if phase == .ready {
                Text("Ready: play one chord now")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if phase == .analyzing {
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

            switch modelStatus {
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
            let isAvailable = await basicPitchAnalyzer.prepare()
            modelStatus = isAvailable ? .ready : .unavailable
        }
        .onChange(of: isSessionActive) { _, isActive in
            if isActive {
                beginListening()
            } else {
                stopListening()
            }
        }
        .onDisappear {
            isSessionActive = false
            stopListening()
        }
    }

    private var statusBadge: some View {
        let label: String
        let color: Color

        switch phase {
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

            if let lastResult {
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

                        let rows = suggestionDisplayRows(from: lastResult)
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
            lastResult = nil
            isSessionActive = true
        }
    }

    private func primaryRootLine(for result: ChordMatch) -> String {
        if let bass = result.bassNoteName {
            return "Root: \(result.rootName) • Lowest note: \(bass)"
        }
        return "Root: \(result.rootName)"
    }

    private func uniqueCandidates(from result: ChordMatch) -> [ChordSuggestion] {
        var unique: [ChordSuggestion] = []
        for candidate in result.candidates {
            if unique.contains(where: { $0.name == candidate.name }) {
                continue
            }
            unique.append(candidate)
        }
        return unique
    }

    private func suggestionDisplayRows(from result: ChordMatch) -> [SuggestionDisplayRow] {
        let candidates = Array(uniqueCandidates(from: result).prefix(5))
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

    private func shouldMergeAsOr(current: ChordSuggestion, next: ChordSuggestion) -> Bool {
        guard current.rootName != next.rootName else { return false }
        let confidenceGap = abs(current.confidence - next.confidence)
        return confidenceGap <= 0.04
    }

    private func beginListening() {
        phase = .ready
        clearCaptureBuffer()
        strongSignalStreak = 0
        sawQuietFrameInReady = false
        startListeningLoop()
    }

    private func stopListening() {
        listeningLoopTask?.cancel()
        listeningLoopTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        phase = .idle
        strongSignalStreak = 0
        sawQuietFrameInReady = false
        clearCaptureBuffer()
    }

    private func startListeningLoop() {
        listeningLoopTask?.cancel()
        listeningLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: listeningPollIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                let now = Date()
                processListeningTick(now: now)
            }
        }
    }

    private func processListeningTick(now: Date) {
        switch phase {
        case .idle, .analyzing:
            return
        case .ready:
            if !isStartSignalFrame {
                sawQuietFrameInReady = true
                strongSignalStreak = 0
                return
            }

            guard sawQuietFrameInReady else { return }
            strongSignalStreak += 1
            guard strongSignalStreak >= onsetRequiredFrames else { return }
            strongSignalStreak = 0
            sawQuietFrameInReady = false
            startCaptureCycle(now: now)
            captureSampleIfNeeded(now: now)
        case .capturing:
            if isSustainSignalFrame {
                lastStrongSignalAt = now
                captureSampleIfNeeded(now: now)
            }

            guard let captureStartedAt else { return }
            let elapsed = now.timeIntervalSince(captureStartedAt)
            if elapsed >= maximumCaptureDuration {
                finalizeCapture()
                return
            }

            guard elapsed >= minimumCaptureDuration else { return }
            guard let lastStrongSignalAt else { return }
            if now.timeIntervalSince(lastStrongSignalAt) >= releaseSilenceBeforeAnalyze {
                finalizeCapture()
            }
        }
    }

    private var isStartSignalFrame: Bool {
        viewModel.currentAmplitude >= captureStartAmplitudeThreshold
            && viewModel.isSignalDetected
            && viewModel.detectedNote != nil
    }

    private var isSustainSignalFrame: Bool {
        viewModel.currentAmplitude >= captureSustainAmplitudeThreshold
            && viewModel.isSignalDetected
            && viewModel.detectedNote != nil
    }

    private func startCaptureCycle(now: Date) {
        clearCaptureBuffer()
        captureStartedAt = now
        lastStrongSignalAt = now
        phase = .capturing
    }

    private func finalizeCapture() {
        let sampleCount = samples.count
        guard sampleCount >= minimumSamplesForAnalysis else {
            phase = .ready
            clearCaptureBuffer()
            return
        }

        analyzeCurrentChord()
    }

    private func clearCaptureBuffer() {
        samples.removeAll()
        lastAcceptedMIDI = nil
        lastAcceptedAt = nil
        captureStartedAt = nil
        lastStrongSignalAt = nil
    }

    private func captureSampleIfNeeded(now: Date) {
        guard isSessionActive, phase == .capturing,
              let detectedNote = viewModel.detectedNote else {
            return
        }

        if let lastAcceptedMIDI,
           let lastAcceptedAt,
           lastAcceptedMIDI == detectedNote.midiNumber,
           now.timeIntervalSince(lastAcceptedAt) < repeatedMIDICooldown {
            return
        }

        samples.append(
            NoteSample(
                pitchClass: ((detectedNote.midiNumber % 12) + 12) % 12,
                midiNumber: detectedNote.midiNumber,
                timestamp: now
            )
        )

        if samples.count > 80 {
            samples.removeFirst(samples.count - 80)
        }

        lastAcceptedMIDI = detectedNote.midiNumber
        lastAcceptedAt = now
    }

    private static func pitchClassCounts(from samples: [NoteSample]) -> [Int: Int] {
        samples.reduce(into: [Int: Int]()) { partial, sample in
            partial[sample.pitchClass, default: 0] += 1
        }
    }

    private func analyzeCurrentChord() {
        guard phase == .capturing else { return }

        phase = .analyzing
        let capturedCounts = Self.pitchClassCounts(from: samples)
        let audioWindow = viewModel.recentAudioWindow(duration: 2.3)
        clearCaptureBuffer()

        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            let modelResult: ChordDetectionResult? = await {
                guard let audioWindow else { return nil }
                return await basicPitchAnalyzer.analyze(audioWindow: audioWindow)
            }()

            await MainActor.run {
                if let modelResult {
                    lastResult = ChordMatch(
                        name: modelResult.name,
                        rootName: modelResult.rootName,
                        confidence: modelResult.confidence,
                        observedNoteNames: modelResult.observedNoteNames,
                        bassNoteName: modelResult.bassNoteName,
                        candidates: modelResult.candidates.map {
                            ChordSuggestion(
                                name: $0.name,
                                rootName: $0.rootName,
                                confidence: $0.confidence
                            )
                        }
                    )
                } else if let fallback = ChordIdentifier.identify(pitchClassCounts: capturedCounts) {
                    lastResult = ChordMatch(
                        name: fallback.name,
                        rootName: fallback.rootName,
                        confidence: fallback.confidence,
                        observedNoteNames: fallback.observedNoteNames,
                        bassNoteName: nil,
                        candidates: fallback.candidates.map {
                            ChordSuggestion(
                                name: $0.name,
                                rootName: $0.rootName,
                                confidence: $0.confidence
                            )
                        }
                    )
                } else {
                    let observed = ChordIdentifier.observedNoteNames(pitchClassCounts: capturedCounts)
                    lastResult = ChordMatch(
                        name: "Unknown",
                        rootName: "--",
                        confidence: 0.0,
                        observedNoteNames: observed,
                        bassNoteName: nil,
                        candidates: []
                    )
                }

                if isSessionActive {
                    isSessionActive = false
                } else {
                    phase = .idle
                }
            }
        }
    }
}
