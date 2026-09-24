import XCTest
@testable import DeepTune

@MainActor
private final class FakeAudioSource: ChordFinderAudioSource {
    var currentAmplitude: Float = 0.0
    var isSignalDetected: Bool = false
    var detectedNote: DetectedNote?

    /// Non-nil so a finished capture actually reaches the analyzer.
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? {
        AudioSampleWindow(samples: [0.0], sampleRate: 22_050)
    }

    /// Nothing playing: below every threshold, no pitch lock.
    func goQuiet() {
        currentAmplitude = 0.0
        isSignalDetected = false
        detectedNote = nil
    }

    /// A note loud enough to open capture, at the given MIDI number.
    func play(midi: Int, amplitude: Float = 0.05) {
        currentAmplitude = amplitude
        isSignalDetected = true
        detectedNote = DetectedNote(
            name: "X",
            octave: 4,
            midiNumber: midi,
            nearestFrequency: 440.0,
            centsFromEqualTempered: 0.0
        )
    }
}

/// Holds every analysis open until the test decides what it returns, so "the
/// model answered while the user was pressing Stop" can be staged exactly.
private actor GatedAnalyzer: ChordAnalyzing {
    private var gate: CheckedContinuation<ChordDetectionResult?, Never>?
    private(set) var analyzeCallCount = 0

    var isHoldingAnalysis: Bool { gate != nil }

    func prepare() -> Bool { true }

    func analyze(audioWindow: AudioSampleWindow) async -> ChordDetectionResult? {
        analyzeCallCount += 1
        return await withCheckedContinuation { gate = $0 }
    }

    func finish(with result: ChordDetectionResult?) {
        gate?.resume(returning: result)
        gate = nil
    }
}

/// Characterisation tests for the capture state machine, plus the session
/// lifecycle behind the Start/Stop button.
@MainActor
final class ChordFinderViewModelTests: XCTestCase {
    private var source: FakeAudioSource!
    private var analyzer: GatedAnalyzer!
    private var model: ChordFinderViewModel!
    private var clock: Date!
    private var sessionEndRequests = 0

    private let cMajor = ChordDetectionResult(
        name: "C",
        rootName: "C",
        confidence: 0.8,
        observedNoteNames: ["C", "E", "G"],
        bassNoteName: "C",
        candidates: []
    )

    override func setUp() async throws {
        try await super.setUp()
        source = FakeAudioSource()
        analyzer = GatedAnalyzer()
        model = ChordFinderViewModel(audioSource: source, analyzer: analyzer, analysisSettleDelay: .zero)
        clock = Date(timeIntervalSinceReferenceDate: 0)
        sessionEndRequests = 0
        model.onRequestSessionEnd = { [weak self] in self?.sessionEndRequests += 1 }
    }

    override func tearDown() async throws {
        // Never leave an analysis parked on the gate.
        await analyzer.finish(with: nil)
        try await super.tearDown()
    }

    /// Advances the fake clock and runs one state-machine step.
    private func tick(after seconds: TimeInterval = 0.12) {
        clock = clock.addingTimeInterval(seconds)
        model.handleTick(now: clock)
    }

    // MARK: - Onset

    func testStartsCapturingAfterAQuietFrameAndTwoLoudFrames() {
        model.beginListening()
        XCTAssertEqual(model.phase, .ready)

        source.goQuiet()
        tick()
        XCTAssertEqual(model.phase, .ready)

        source.play(midi: 60)
        tick()
        XCTAssertEqual(model.phase, .ready, "one loud frame is not an onset")

        tick()
        XCTAssertEqual(model.phase, .capturing, "two consecutive loud frames open capture")
    }

    func testNeverStartsWithoutAQuietFrameFirst() {
        model.beginListening()

        // Signal already loud when the session opens — e.g. the guitar is still
        // ringing, or the room is noisy above the threshold.
        source.play(midi: 60)
        for _ in 0..<50 { tick() }

        XCTAssertEqual(model.phase, .ready, "stays stuck in ready with no quiet frame to arm on")
    }

    func testDoesNotStartWhilePitchIsUnlockedEvenIfLoud() {
        model.beginListening()
        source.goQuiet()
        tick()

        // Loud, but the monophonic tracker reports no note — which is what a
        // strummed chord often looks like.
        source.currentAmplitude = 0.9
        source.isSignalDetected = true
        source.detectedNote = nil
        for _ in 0..<20 { tick() }

        XCTAssertEqual(model.phase, .ready)
    }

    // MARK: - Capture window

    func testFinalizesAfterTheSignalDropsForLongEnough() {
        startCapturing()

        // Collect enough distinct notes to clear the minimum-samples gate.
        for midi in [60, 64, 67, 60, 64, 67] {
            source.play(midi: midi)
            tick()
        }
        XCTAssertEqual(model.phase, .capturing)

        source.goQuiet()
        tick(after: 0.5) // past the minimum capture duration
        tick(after: 0.4) // past the release-silence threshold
        XCTAssertEqual(model.phase, .analyzing)
    }

    func testFinalizesWhenTheMaximumCaptureDurationIsReached() {
        startCapturing()

        var midi = 60
        for _ in 0..<30 {
            source.play(midi: midi)
            midi = midi == 60 ? 64 : 60
            tick(after: 0.1)
            if model.phase != .capturing { break }
        }

        XCTAssertEqual(model.phase, .analyzing, "capture cannot run past its ceiling")
    }

    // MARK: - The silent give-up

    func testReturnsToReadyWithoutAnyResultWhenTooFewSamplesWereCollected() {
        startCapturing()

        // One sustained note produces too few distinct samples to analyse.
        source.play(midi: 60)
        tick()
        source.goQuiet()
        tick(after: 0.5)
        tick(after: 0.4)

        XCTAssertEqual(model.phase, .ready, "drops back to ready")
        XCTAssertNil(model.lastResult, "and says nothing about having tried")
    }

    // MARK: - Session control

    func testStopListeningResetsToIdle() {
        startCapturing()
        model.stopListening()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.samples.isEmpty)
    }

    func testTicksAreIgnoredWhileIdle() {
        source.play(midi: 60)
        for _ in 0..<10 { tick() }

        XCTAssertEqual(model.phase, .idle)
    }

    // MARK: - Session lifecycle (the Start/Stop button)

    func testStoppingWhileReadyReturnsToIdle() {
        model.beginListening()
        model.stopListening()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(sessionEndRequests, 0)
    }

    func testStoppingWhileCapturingNeverStartsAnAnalysis() async {
        startCapturing()
        source.play(midi: 64)
        tick()
        model.stopListening()

        // Ticks after the stop must not revive the capture.
        source.goQuiet()
        tick(after: 0.5)
        tick(after: 0.4)

        let calls = await analyzer.analyzeCallCount
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.samples.isEmpty)
        XCTAssertNil(model.analysisTask)
        XCTAssertEqual(calls, 0)
    }

    func testCompletedAnalysisShowsTheResultAndClosesTheSession() async throws {
        let pending = try await driveToHeldAnalysis()

        await analyzer.finish(with: cMajor)
        await pending.value

        XCTAssertEqual(model.lastResult?.name, "C")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(sessionEndRequests, 1, "a one-shot session closes itself once")
    }

    func testStoppingDuringAnalysisDiscardsTheResult() async throws {
        let pending = try await driveToHeldAnalysis()

        model.stopListening()
        await analyzer.finish(with: cMajor)
        await pending.value

        XCTAssertNil(model.lastResult, "a stopped analysis must not show up afterwards")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(sessionEndRequests, 0)
    }

    func testStoppingAndRestartingDuringAnalysisKeepsTheNewSession() async throws {
        let pending = try await driveToHeldAnalysis()

        model.stopListening()
        model.beginListening()
        await analyzer.finish(with: cMajor)
        await pending.value

        XCTAssertEqual(model.phase, .ready, "the new session must survive the old analysis")
        XCTAssertNil(model.lastResult, "and must not inherit its result")
        XCTAssertEqual(sessionEndRequests, 0, "the old analysis must not close the new session")
    }

    func testStartingANewSessionDuringAnalysisDiscardsTheOldResult() async throws {
        let pending = try await driveToHeldAnalysis()

        model.beginListening()
        await analyzer.finish(with: cMajor)
        await pending.value

        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.lastResult)
        XCTAssertEqual(sessionEndRequests, 0)
    }

    func testStoppingDuringTheSettleDelayNeverReachesTheModel() async throws {
        // A settle delay long enough that only cancellation can end it.
        model = ChordFinderViewModel(audioSource: source, analyzer: analyzer, analysisSettleDelay: .seconds(60))
        model.onRequestSessionEnd = { [weak self] in self?.sessionEndRequests += 1 }
        driveToAnalyzing()
        let pending = try XCTUnwrap(model.analysisTask)

        model.stopListening()
        await pending.value

        let calls = await analyzer.analyzeCallCount
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.lastResult)
        XCTAssertEqual(model.phase, .idle)
    }

    func testStartingASessionClearsThePreviousResult() async throws {
        let pending = try await driveToHeldAnalysis()
        await analyzer.finish(with: cMajor)
        await pending.value
        XCTAssertNotNil(model.lastResult)

        model.beginListening()

        XCTAssertNil(model.lastResult, "a new session is a new question")
        XCTAssertEqual(model.phase, .ready)
    }

    func testFallsBackToTemplateMatchingWhenTheModelHasNoAnswer() async throws {
        // The captured notes are C, E and G, so the fallback should name C major.
        let pending = try await driveToHeldAnalysis()

        await analyzer.finish(with: nil)
        await pending.value

        XCTAssertEqual(model.lastResult?.name, "C")
        XCTAssertEqual(sessionEndRequests, 1)
    }

    func testStoppingTwiceIsHarmless() async throws {
        let pending = try await driveToHeldAnalysis()

        model.stopListening()
        model.stopListening()
        await analyzer.finish(with: cMajor)
        await pending.value

        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.lastResult)
        XCTAssertEqual(sessionEndRequests, 0)
    }

    // MARK: - Helpers

    /// Plays C-E-G, lets the capture finish, and returns once the analysis is
    /// parked inside the analyzer waiting for the test to answer.
    private func driveToHeldAnalysis() async throws -> Task<Void, Never> {
        driveToAnalyzing()
        let pending = try XCTUnwrap(model.analysisTask)

        for _ in 0..<1_000 {
            if await analyzer.isHoldingAnalysis { return pending }
            await Task.yield()
        }
        XCTFail("the analysis never reached the analyzer")
        return pending
    }

    private func driveToAnalyzing() {
        startCapturing()
        for midi in [64, 67, 60, 64, 67] {
            source.play(midi: midi)
            tick()
        }
        source.goQuiet()
        tick(after: 0.5)
        tick(after: 0.4)
        XCTAssertEqual(model.phase, .analyzing, "precondition: the capture finished")
    }

    private func startCapturing() {
        model.beginListening()
        source.goQuiet()
        tick()
        source.play(midi: 60)
        tick()
        tick()
        XCTAssertEqual(model.phase, .capturing, "precondition: capture is open")
    }
}
