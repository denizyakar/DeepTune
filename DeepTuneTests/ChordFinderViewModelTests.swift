import XCTest
@testable import DeepTune

@MainActor
private final class FakeAudioSource: ChordFinderAudioSource {
    var currentAmplitude: Float = 0.0
    var isSignalDetected: Bool = false
    var detectedNote: DetectedNote?

    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? { nil }

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

/// Characterisation tests for the capture state machine. These lock in today's
/// behaviour — including the parts we already know are wrong — so the behaviour
/// round can change them deliberately.
@MainActor
final class ChordFinderViewModelTests: XCTestCase {
    private var source: FakeAudioSource!
    private var model: ChordFinderViewModel!
    private var clock: Date!

    override func setUp() async throws {
        try await super.setUp()
        source = FakeAudioSource()
        model = ChordFinderViewModel(audioSource: source)
        clock = Date(timeIntervalSinceReferenceDate: 0)
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

    // MARK: - Helpers

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
