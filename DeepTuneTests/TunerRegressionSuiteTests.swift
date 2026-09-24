import XCTest
@testable import DeepTune

/// Runs the executable form of claude-rules/TUNER_QUALITY_BAR.md against
/// synthetic plucks. It does not replace the physical test matrix, but a
/// smoothing or acceptance change that breaks the bar fails here first.
@MainActor
final class TunerRegressionSuiteTests: XCTestCase {
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

    private func assertPassed(_ result: RegressionSuiteResult, _ instrument: Instrument, line: UInt = #line) {
        for check in result.checks where !check.passed {
            XCTFail("\(instrument.name) — \(check.name): \(check.detail)", line: line)
        }
    }
}
