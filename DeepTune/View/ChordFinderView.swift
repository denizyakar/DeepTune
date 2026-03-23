import SwiftUI

struct ChordFinderView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Binding var isSessionActive: Bool

    private let basicPitchAnalyzer = BasicPitchChordAnalyzer.shared

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
        let confidence: Double
        let observedNoteNames: [String]
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

            if !basicPitchAnalyzer.isModelAvailable {
                Text("ML model not found in bundle (nmp.mlpackage/mlmodelc). Running fallback detector.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.warning)
            }
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

                Text("Observed notes: \(lastResult.observedNoteNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
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

    private func analyzeCurrentChord() {
        guard phase == .capturing else { return }

        phase = .analyzing
        let capturedSamples = samples
        let audioWindow = viewModel.recentAudioWindow(duration: 2.3)
        clearCaptureBuffer()

        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            let modelResult: ChordDetectionResult? = {
                guard let audioWindow else { return nil }
                return basicPitchAnalyzer.analyze(audioWindow: audioWindow)
            }()

            await MainActor.run {
                if let modelResult {
                    lastResult = ChordMatch(
                        name: modelResult.name,
                        confidence: modelResult.confidence,
                        observedNoteNames: modelResult.observedNoteNames
                    )
                } else if let fallback = ChordIdentifier.identify(from: capturedSamples) {
                    lastResult = fallback
                } else {
                    let observed = ChordIdentifier.observedNoteNames(from: capturedSamples)
                    lastResult = ChordMatch(name: "Unknown", confidence: 0.0, observedNoteNames: observed)
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

private enum ChordIdentifier {
    private struct Template {
        let suffix: String
        let intervals: [Int]
    }

    private static let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private static let templates: [Template] = [
        Template(suffix: "", intervals: [0, 4, 7]),
        Template(suffix: "m", intervals: [0, 3, 7]),
        Template(suffix: "5", intervals: [0, 7]),
        Template(suffix: "sus2", intervals: [0, 2, 7]),
        Template(suffix: "sus4", intervals: [0, 5, 7]),
        Template(suffix: "dim", intervals: [0, 3, 6]),
        Template(suffix: "aug", intervals: [0, 4, 8]),
        Template(suffix: "7", intervals: [0, 4, 7, 10]),
        Template(suffix: "maj7", intervals: [0, 4, 7, 11]),
        Template(suffix: "m7", intervals: [0, 3, 7, 10])
    ]

    private struct MatchScore {
        let root: Int
        let suffix: String
        let score: Double
        let expectedPitchClasses: Set<Int>
        let matchedWeight: Double
        let missingCount: Int
        let extraWeight: Double
    }

    static func identify(from samples: [ChordFinderView.NoteSample]) -> ChordFinderView.ChordMatch? {
        let counts = pitchClassCounts(from: samples)
        guard !counts.isEmpty else { return nil }

        let observedSet = filteredObservedPitchClasses(from: counts)
        guard observedSet.count >= 2 else { return nil }

        let rankedMatches = rankedMatches(counts: counts, observedSet: observedSet)
        guard let best = rankedMatches.first else { return nil }
        guard best.score > 1.2 else { return nil }

        if best.expectedPitchClasses.count >= 3, observedSet.count < 3 {
            return nil
        }

        let totalWeight = Double(counts.values.reduce(0, +))
        let matchedCoverage = best.matchedWeight / max(1.0, totalWeight)
        let requiredCoverage = best.expectedPitchClasses.count == 2 ? 0.50 : 0.58
        guard matchedCoverage >= requiredCoverage else { return nil }

        let matchedPitchClassCount = Double(best.expectedPitchClasses.intersection(observedSet).count)
        let setCoverage = matchedPitchClassCount / Double(best.expectedPitchClasses.count)
        let requiredSetCoverage = best.expectedPitchClasses.count == 2 ? 0.50 : 0.66
        guard setCoverage >= requiredSetCoverage else { return nil }

        let ambiguityMargin: Double
        if rankedMatches.count >= 2 {
            let second = rankedMatches[1]
            ambiguityMargin = max(0.0, min(1.0, (best.score - second.score) / max(1.0, abs(best.score))))
            guard ambiguityMargin >= 0.08 else { return nil }
        } else {
            ambiguityMargin = 1.0
        }

        let extraPenalty = (best.extraWeight / max(1.0, totalWeight)) * 0.22
        let confidence = max(
            0.12,
            min(
                0.82,
                0.20 + (matchedCoverage * 0.34) + (setCoverage * 0.28) + (ambiguityMargin * 0.20) - extraPenalty
            )
        )
        guard confidence >= 0.26 else { return nil }

        return ChordFinderView.ChordMatch(
            name: pitchClassNames[best.root] + best.suffix,
            confidence: confidence,
            observedNoteNames: observedSet.sorted().map { pitchClassNames[$0] }
        )
    }

    static func observedNoteNames(from samples: [ChordFinderView.NoteSample]) -> [String] {
        let counts = pitchClassCounts(from: samples)
        let observedSet = filteredObservedPitchClasses(from: counts)
        return observedSet.sorted().map { pitchClassNames[$0] }
    }

    private static func pitchClassCounts(from samples: [ChordFinderView.NoteSample]) -> [Int: Int] {
        samples.reduce(into: [Int: Int]()) { partial, sample in
            partial[sample.pitchClass, default: 0] += 1
        }
    }

    private static func filteredObservedPitchClasses(from counts: [Int: Int]) -> Set<Int> {
        guard let maxWeight = counts.values.max() else { return [] }
        let threshold = max(1, Int(Double(maxWeight) * 0.16))
        return Set(counts.filter { $0.value >= threshold }.map { $0.key })
    }

    private static func rankedMatches(counts: [Int: Int], observedSet: Set<Int>) -> [MatchScore] {
        var matches: [MatchScore] = []
        for root in 0..<12 {
            for template in templates {
                let expected = Set(template.intervals.map { (root + $0) % 12 })
                let matchedWeight = expected.reduce(0.0) { partial, pitchClass in
                    partial + Double(counts[pitchClass] ?? 0)
                }
                let missingCount = expected.filter { counts[$0] == nil }.count
                let extraWeight = observedSet.subtracting(expected).reduce(0.0) { partial, pitchClass in
                    partial + Double(counts[pitchClass] ?? 0)
                }

                let score = (matchedWeight * 2.0) - (Double(missingCount) * 3.0) - (extraWeight * 1.35)
                matches.append(
                    MatchScore(
                        root: root,
                        suffix: template.suffix,
                        score: score,
                        expectedPitchClasses: expected,
                        matchedWeight: matchedWeight,
                        missingCount: missingCount,
                        extraWeight: extraWeight
                    )
                )
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.missingCount < rhs.missingCount
            }
            return lhs.score > rhs.score
        }
    }
}
