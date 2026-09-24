import XCTest
@testable import DeepTune

@MainActor
final class TunerRegressionSuiteTests: XCTestCase {
    func testTuningPresetIntegritySuitePasses() {
        let result = TunerRegressionSuite.runTuningPresetIntegritySuite(instrument: InstrumentCatalog.guitar6)
        XCTAssertTrue(result.passed, result.summaryLine)
    }
}
