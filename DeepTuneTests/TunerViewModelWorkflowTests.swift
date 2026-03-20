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

    func emit(pitch: Float, amplitude: Float) {}
}

@MainActor
final class TunerViewModelWorkflowTests: XCTestCase {
    func testSwitchingInstrumentAndTuningUpdatesTargetNote() {
        let mockConductor = MockConductor()
        let viewModel = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor
        )
        let targetTuning = InstrumentCatalog.guitar7DropA

        viewModel.setInstrumentAndTuning(instrument: InstrumentCatalog.guitar7, tuning: targetTuning)

        XCTAssertEqual(viewModel.currentInstrument.type, .guitar7)
        XCTAssertEqual(viewModel.currentTuning, targetTuning)
        XCTAssertEqual(viewModel.targetNote?.fullName, targetTuning.notes.first?.fullName)
    }

    func testManualSessionMetricsResetOnModeTransition() {
        let mockConductor = MockConductor()
        let viewModel = TunerViewModel(
            instrument: InstrumentCatalog.guitar6,
            conductor: mockConductor
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

    func testPersistedInstrumentTuningAndAutoProgressAreRestored() {
        let suiteName = "DeepTuneTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
