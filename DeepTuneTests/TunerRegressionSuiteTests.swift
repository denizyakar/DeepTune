import XCTest
@testable import DeepTune

/// Runs the executable form of claude-rules/TUNER_QUALITY_BAR.md against
/// synthetic plucks. It does not replace the physical test matrix, but a
/// smoothing or acceptance change that breaks the bar fails here first.
@MainActor
final class TunerRegressionSuiteTests: XCTestCase {
    /// PitchTap delivers one reading per 4096-sample buffer: 11.7 Hz at 48 kHz,
    /// and 11.71 Hz measured on an iPhone 11. The suites default to 60 Hz, so
    /// the bar also has to hold at the rate a phone actually produces.
    private static let deviceFrameRate = 11.7
    func testTuningPresetIntegritySuitePasses() {
        let result = TunerRegressionSuite.runTuningPresetIntegritySuite(instrument: InstrumentCatalog.guitar6)
        XCTAssertTrue(result.passed, result.summaryLine)
    }

    func testAutoTunerMeetsQualityBarOnEverySelectableInstrument() {
        for instrument in InstrumentCatalog.selectableInstruments {
            assertPassed(TunerRegressionSuite.runAutoQualityBar(instrument: instrument), instrument)
        }
    }

    func testManualTunerStaysStableOnEverySelectableInstrument() {
        for instrument in InstrumentCatalog.selectableInstruments {
            assertPassed(TunerRegressionSuite.runManualStabilitySuite(instrument: instrument), instrument)
        }
    }

    func testAutoTunerMeetsQualityBarAtDeviceFrameRate() {
        for instrument in InstrumentCatalog.selectableInstruments {
            assertPassed(
                TunerRegressionSuite.runAutoQualityBar(instrument: instrument, frameRate: Self.deviceFrameRate),
                instrument
            )
        }
    }

    func testManualTunerStaysStableAtDeviceFrameRate() {
        for instrument in InstrumentCatalog.selectableInstruments {
            assertPassed(
                TunerRegressionSuite.runManualStabilitySuite(instrument: instrument, frameRate: Self.deviceFrameRate),
                instrument
            )
        }
    }

    private func assertPassed(_ result: RegressionSuiteResult, _ instrument: Instrument, line: UInt = #line) {
        for check in result.checks where !check.passed {
            XCTFail("\(instrument.name) — \(check.name): \(check.detail)", line: line)
        }
    }
}
