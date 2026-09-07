import XCTest
import Combine
@testable import DeepTune

private final class MockConductor: TunerConductorType {
    var dataPublisher: AnyPublisher<PitchData, Never> {
        Empty<PitchData, Never>(completeImmediately: true).eraseToAnyPublisher()
    }

    func start() {}
    func stop() {}
    func setTrackingTargetFrequency(_ frequency: Float?) {}
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? { nil }
    func setRecentAudioCaptureEnabled(_ enabled: Bool) {}

    func emit(pitch: Float, amplitude: Float) {}
}

@MainActor
final class TunerViewModelWorkflowTests: XCTestCase {
    // TunerViewModel persists to UserDefaults on init, so every test needs its own
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

    func testSwitchingInstrumentAndTuningUpdatesTargetNote() throws {
        let mockConductor = MockConductor()
        let viewModel = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor,
            userDefaults: try makeIsolatedDefaults()
        )
        let targetTuning = InstrumentCatalog.guitar7DropA

        viewModel.setInstrumentAndTuning(instrument: InstrumentCatalog.guitar7, tuning: targetTuning)

        XCTAssertEqual(viewModel.currentInstrument.type, .guitar7)
        XCTAssertEqual(viewModel.currentTuning, targetTuning)
        XCTAssertEqual(viewModel.targetNote?.fullName, targetTuning.notes.first?.fullName)
    }

    func testManualSessionMetricsResetOnModeTransition() throws {
        let mockConductor = MockConductor()
        let viewModel = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor,
            userDefaults: try makeIsolatedDefaults()
        )
        viewModel.setActiveMode(.manual)
        var timestamp = Date()

        for _ in 0..<6 {
            viewModel.debugInjectFrame(pitch: 110.0, amplitude: 0.12, timestamp: timestamp)
            timestamp.addTimeInterval(0.02)
        }

        XCTAssertNotNil(viewModel.manualLowestFrequency)
        XCTAssertNotNil(viewModel.manualHighestFrequency)

        viewModel.setActiveMode(.auto)
        viewModel.setActiveMode(.manual)

        XCTAssertNil(viewModel.manualLowestFrequency)
        XCTAssertNil(viewModel.manualHighestFrequency)
    }

    func testPersistedInstrumentTuningAndAutoProgressAreRestored() throws {
        let defaults = try makeIsolatedDefaults()
        let mockConductor = MockConductor()
        let firstSession = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor,
            userDefaults: defaults
        )
        firstSession.setInstrumentAndTuning(
            instrument: InstrumentCatalog.bass4,
            tuning: InstrumentCatalog.bass4DropC
        )
        firstSession.isAutoProgressEnabled = true

        let secondSession = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor,
            userDefaults: defaults
        )

        XCTAssertEqual(secondSession.currentInstrument.type, .bass)
        XCTAssertEqual(secondSession.currentTuning.name, InstrumentCatalog.bass4DropC.name)
        XCTAssertEqual(secondSession.currentTuning.notes.map(\.fullName), InstrumentCatalog.bass4DropC.notes.map(\.fullName))
        XCTAssertTrue(secondSession.isAutoProgressEnabled)
    }
}
