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
}
