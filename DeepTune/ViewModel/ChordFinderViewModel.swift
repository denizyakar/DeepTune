import Foundation
import Observation

/// The slice of the tuner the chord finder actually reads. Narrowing it to this
/// lets the capture state machine be driven by a fake in tests.
protocol ChordFinderAudioSource: AnyObject {
    var currentAmplitude: Float { get }
    var isSignalDetected: Bool { get }
    var detectedNote: DetectedNote? { get }
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow?
}

extension TunerSession: ChordFinderAudioSource {}

@Observable
final class ChordFinderViewModel {
    enum Phase {
        case idle
        case ready
        case capturing
        case analyzing
    }

    enum ModelStatus {
        case loading
        case ready
        case unavailable
    }

    struct NoteSample: Identifiable {
        let id = UUID()
        let pitchClass: Int
        let midiNumber: Int
        let timestamp: Date
    }

    struct ChordSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let rootName: String
        let confidence: Double
    }

    struct ChordMatch {
        let name: String
        let rootName: String
        let confidence: Double
        let observedNoteNames: [String]
        let bassNoteName: String?
        let candidates: [ChordSuggestion]
    }

    private(set) var phase: Phase = .idle
    private(set) var modelStatus: ModelStatus = .loading
    private(set) var lastResult: ChordMatch?
    private(set) var samples: [NoteSample] = []

    /// Called when an analysis finishes and the one-shot session should close.
    var onRequestSessionEnd: (() -> Void)?

    private let audioSource: ChordFinderAudioSource
    private let analyzer: any ChordAnalyzing

    private var lastAcceptedMIDI: Int?
    private var lastAcceptedAt: Date?
    private var captureStartedAt: Date?
    private var lastStrongSignalAt: Date?
    private var strongSignalStreak = 0
    private var sawQuietFrameInReady = false
    /// Readable so tests can await an analysis they have held open.
    private(set) var analysisTask: Task<Void, Never>?
    /// Changes on every start and stop, so an analysis can tell whether the session
    /// it was started for is still the current one when its result arrives.
    private var sessionID = 0

    let listeningPollIntervalNanoseconds: UInt64 = 120_000_000
    private let repeatedMIDICooldown: TimeInterval = 0.08
    private let captureStartAmplitudeThreshold: Float = 0.020
    private let captureSustainAmplitudeThreshold: Float = 0.011
    private let onsetRequiredFrames = 2
    private let minimumCaptureDuration: TimeInterval = 0.45
    private let releaseSilenceBeforeAnalyze: TimeInterval = 0.32
    private let maximumCaptureDuration: TimeInterval = 2.20
    private let minimumSamplesForAnalysis = 5
    private let analysisWindowDuration: TimeInterval = 2.3
    private let analysisSettleDelay: Duration

    init(
        audioSource: ChordFinderAudioSource,
        analyzer: any ChordAnalyzing = BasicPitchChordAnalyzer.shared,
        analysisSettleDelay: Duration = .milliseconds(220)
    ) {
        self.audioSource = audioSource
        self.analyzer = analyzer
        self.analysisSettleDelay = analysisSettleDelay
    }

    // MARK: - Model

    func prepareModel() async {
        let isAvailable = await analyzer.prepare()
        modelStatus = isAvailable ? .ready : .unavailable
    }

    // MARK: - Session

    /// Starts a fresh session. The previous result is cleared: a new session is a
    /// new question.
    func beginListening() {
        endCurrentSession()
        sessionID += 1
        lastResult = nil
        phase = .ready
    }

    /// Ends the session and discards any analysis still in flight. Safe to call
    /// more than once — every path that can end a session calls it.
    func stopListening() {
        endCurrentSession()
        sessionID += 1
        phase = .idle
    }

    private func endCurrentSession() {
        analysisTask?.cancel()
        analysisTask = nil
        strongSignalStreak = 0
        sawQuietFrameInReady = false
        clearCaptureBuffer()
    }

    /// Polls the audio source until cancelled. Cancellation is the caller's job —
    /// drive this from `task(id:)` so leaving the screen tears it down.
    func runListeningLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: listeningPollIntervalNanoseconds)
            guard !Task.isCancelled else { break }
            handleTick(now: Date())
        }
    }

    // MARK: - Capture state machine

    /// One step of the state machine. Takes `now` so tests can drive it without a clock.
    func handleTick(now: Date) {
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
        audioSource.currentAmplitude >= captureStartAmplitudeThreshold
            && audioSource.isSignalDetected
            && audioSource.detectedNote != nil
    }

    private var isSustainSignalFrame: Bool {
        audioSource.currentAmplitude >= captureSustainAmplitudeThreshold
            && audioSource.isSignalDetected
            && audioSource.detectedNote != nil
    }

    private func startCaptureCycle(now: Date) {
        clearCaptureBuffer()
        captureStartedAt = now
        lastStrongSignalAt = now
        phase = .capturing
    }

    private func finalizeCapture() {
        guard samples.count >= minimumSamplesForAnalysis else {
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
        guard phase == .capturing, let detectedNote = audioSource.detectedNote else { return }

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

    // MARK: - Analysis

    private func analyzeCurrentChord() {
        guard phase == .capturing else { return }

        phase = .analyzing
        let capturedCounts = Self.pitchClassCounts(from: samples)
        let audioWindow = audioSource.recentAudioWindow(duration: analysisWindowDuration)
        clearCaptureBuffer()

        let analysisSessionID = sessionID
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.analysisSettleDelay)
            guard self.isAwaitingResult(for: analysisSessionID) else { return }

            let modelResult: ChordDetectionResult? = await {
                guard let audioWindow else { return nil }
                return await self.analyzer.analyze(audioWindow: audioWindow)
            }()

            // CoreML inference can't be interrupted, so the session may have been
            // stopped — or stopped and restarted — while it ran. Cancellation alone
            // isn't enough: the stop can reach us after the model has returned.
            guard self.isAwaitingResult(for: analysisSessionID) else { return }
            self.applyResult(modelResult: modelResult, capturedCounts: capturedCounts)
        }
    }

    private func isAwaitingResult(for analysisSessionID: Int) -> Bool {
        !Task.isCancelled && analysisSessionID == sessionID && phase == .analyzing
    }

    private func applyResult(modelResult: ChordDetectionResult?, capturedCounts: [Int: Int]) {
        if let modelResult {
            lastResult = ChordMatch(
                name: modelResult.name,
                rootName: modelResult.rootName,
                confidence: modelResult.confidence,
                observedNoteNames: modelResult.observedNoteNames,
                bassNoteName: modelResult.bassNoteName,
                candidates: modelResult.candidates.map {
                    ChordSuggestion(name: $0.name, rootName: $0.rootName, confidence: $0.confidence)
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
                    ChordSuggestion(name: $0.name, rootName: $0.rootName, confidence: $0.confidence)
                }
            )
        } else {
            lastResult = ChordMatch(
                name: String(localized: "Unknown", comment: "Shown when no chord could be identified."),
                rootName: "--",
                confidence: 0.0,
                observedNoteNames: ChordIdentifier.observedNoteNames(pitchClassCounts: capturedCounts),
                bassNoteName: nil,
                candidates: []
            )
        }

        phase = .idle
        onRequestSessionEnd?()
    }

    static func pitchClassCounts(from samples: [NoteSample]) -> [Int: Int] {
        samples.reduce(into: [Int: Int]()) { partial, sample in
            partial[sample.pitchClass, default: 0] += 1
        }
    }
}
