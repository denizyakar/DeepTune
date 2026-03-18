import XCTest
@testable import DeepTune

final class TuningPresetCatalogTests: XCTestCase {
    func testCommonGroupIsFirstAndContainsExpectedTunings() {
        let groups = InstrumentCatalog.tuningGroups(for: InstrumentCatalog.guitar6)

        XCTAssertFalse(groups.isEmpty)
        XCTAssertEqual(groups.first?.title, "Common")

        let expectedCommonTunings = [
            "E Standard",
            "Eb Standard",
            "D Standard",
            "C# Standard",
            "C Standard",
            "Drop D",
            "Drop C#",
            "Drop C",
            "B Standard",
            "Drop B",
            "Drop A"
        ]

        let commonNames = Set(groups.first?.tunings.map(\.name) ?? [])
        for tuningName in expectedCommonTunings {
            XCTAssertTrue(commonNames.contains(tuningName), "Missing common tuning: \(tuningName)")
        }
    }

    func testAllGuitarSixTuningsHaveAscendingFrequencies() {
        let groups = InstrumentCatalog.tuningGroups(for: InstrumentCatalog.guitar6)
        let tunings = groups.flatMap(\.tunings)

        XCTAssertFalse(tunings.isEmpty)

        for tuning in tunings {
            XCTAssertEqual(tuning.notes.count, 6, "Invalid string count for \(tuning.name)")
            for (lhs, rhs) in zip(tuning.notes, tuning.notes.dropFirst()) {
                XCTAssertLessThan(lhs.frequency, rhs.frequency, "Frequency order is invalid in \(tuning.name)")
            }
        }
    }
}
