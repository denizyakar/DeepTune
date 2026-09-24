import XCTest
@testable import DeepTune

private final class MockConductor: TunerConductorType {
    // Built up front so frames emitted before anyone iterates are buffered.
    private let (updates, continuation) = AsyncStream.makeStream(of: PitchData.self)

    func pitchUpdates() -> AsyncStream<PitchData> {
        updates
    }

    func start() {}
    func stop() {}
    func setTrackingTargetFrequency(_ frequency: Float?) {}
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? { nil }
    func setRecentAudioCaptureEnabled(_ enabled: Bool) {}

    func emit(pitch: Float, amplitude: Float) {
        continuation.yield(PitchData(pitch: pitch, amplitude: amplitude))
    }

    func finishUpdates() {
        continuation.finish()
    }
}

@MainActor
final class TunerWorkflowTests: XCTestCase {
    // The tuner persists to UserDefaults on init, so every test needs its own
    // suite: the default suite is the host app's, and tests would rewrite the user's
    // saved instrument and leak state into each other.
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "DeepTuneTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "Unable to create isolated UserDefaults suite"
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeTuner(
        conductor: MockConductor = MockConductor(),
        defaults: UserDefaults
    ) -> (session: TunerSession, auto: AutoTunerViewModel, manual: ManualTunerViewModel) {
        let session = TunerSession(
            instrument: InstrumentCatalog.guitar6,
            conductor: conductor,
            userDefaults: defaults
        )
        return (
            session,
            AutoTunerViewModel(session: session, userDefaults: defaults),
            ManualTunerViewModel(session: session)
        )
    }

    func testSwitchingInstrumentAndTuningUpdatesTargetNote() throws {
        let (session, auto, _) = makeTuner(defaults: try makeIsolatedDefaults())
        let targetTuning = InstrumentCatalog.guitar7DropA

        session.setInstrumentAndTuning(instrument: InstrumentCatalog.guitar7, tuning: targetTuning)

        XCTAssertEqual(session.currentInstrument.type, .guitar7)
        XCTAssertEqual(session.currentTuning, targetTuning)
        XCTAssertEqual(auto.targetNote?.fullName, targetTuning.notes.first?.fullName)
    }

    func testConductorFramesReachTheSession() async throws {
        let mockConductor = MockConductor()
        let (session, _, _) = makeTuner(conductor: mockConductor, defaults: try makeIsolatedDefaults())
        mockConductor.emit(pitch: 110.0, amplitude: 0.12)
        mockConductor.finishUpdates()

        // Returns once the finished stream is drained.
        await session.processPitchUpdates()

        XCTAssertEqual(session.currentPitch, 110.0)
        XCTAssertTrue(session.isSignalDetected)
    }

    func testManualSessionMetricsResetOnModeTransition() throws {
        let (session, _, manual) = makeTuner(defaults: try makeIsolatedDefaults())
        session.setActiveMode(.manual)
        var timestamp = Date()

        for _ in 0..<6 {
            session.debugInjectFrame(pitch: 110.0, amplitude: 0.12, timestamp: timestamp)
            timestamp.addTimeInterval(0.02)
        }

        XCTAssertNotNil(manual.manualLowestFrequency)
        XCTAssertNotNil(manual.manualHighestFrequency)

        session.setActiveMode(.auto)
        session.setActiveMode(.manual)

        XCTAssertNil(manual.manualLowestFrequency)
        XCTAssertNil(manual.manualHighestFrequency)
    }

    func testUnselectableInstrumentIsNotRestored() throws {
        let defaults = try makeIsolatedDefaults()

        // The 7-string is unfinished and filtered out of the picker, so restoring
        // it would strand the user in a mode the UI offers no way to reach.
        let polluted = makeTuner(defaults: defaults).session
        polluted.setInstrumentAndTuning(
            instrument: InstrumentCatalog.guitar7,
            tuning: InstrumentCatalog.guitar7DropA
        )

        let restored = makeTuner(defaults: defaults).session

        XCTAssertEqual(restored.currentInstrument.type, .guitar6)
    }

    func testPersistedInstrumentTuningAndAutoProgressAreRestored() throws {
        let defaults = try makeIsolatedDefaults()
        let first = makeTuner(defaults: defaults)
        first.session.setInstrumentAndTuning(
            instrument: InstrumentCatalog.bass4,
            tuning: InstrumentCatalog.bass4DropC
        )
        first.auto.isAutoProgressEnabled = true

        let second = makeTuner(defaults: defaults)

        XCTAssertEqual(second.session.currentInstrument.type, .bass)
        XCTAssertEqual(second.session.currentTuning.name, InstrumentCatalog.bass4DropC.name)
        XCTAssertEqual(second.session.currentTuning.notes.map(\.fullName), InstrumentCatalog.bass4DropC.notes.map(\.fullName))
        XCTAssertTrue(second.auto.isAutoProgressEnabled)
    }
}
