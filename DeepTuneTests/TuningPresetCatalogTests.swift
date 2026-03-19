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

    func testExtendedInstrumentCatalogIncludesExpectedInstruments() {
        let names = Set(InstrumentCatalog.allInstruments.map(\.name))

        XCTAssertTrue(names.contains("6-String Guitar"))
        XCTAssertTrue(names.contains("7-String Guitar"))
        XCTAssertTrue(names.contains("4-String Bass"))
        XCTAssertTrue(names.contains("4-String Ukulele"))
    }

    func testAllInstrumentTuningsHaveConsistentStringCountsAndAscendingFrequencies() {
        for instrument in InstrumentCatalog.allInstruments {
            let groups = InstrumentCatalog.tuningGroups(for: instrument)
            XCTAssertFalse(groups.isEmpty, "Missing tuning groups for \(instrument.name)")

            let tunings = groups.flatMap(\.tunings)
            XCTAssertFalse(tunings.isEmpty, "Missing tunings for \(instrument.name)")

            let expectedStringCount = instrument.defaultTuning.notes.count
            for tuning in tunings {
                XCTAssertEqual(
                    tuning.notes.count,
                    expectedStringCount,
                    "Invalid string count in \(instrument.name) / \(tuning.name)"
                )

                for (lhs, rhs) in zip(tuning.notes, tuning.notes.dropFirst()) {
                    XCTAssertLessThan(
                        lhs.frequency,
                        rhs.frequency,
                        "Frequency order is invalid in \(instrument.name) / \(tuning.name)"
                    )
                }
            }
        }
    }

    func testNewInstrumentsExposeMultipleTuningGroups() {
        let newInstruments = [InstrumentCatalog.guitar7, InstrumentCatalog.bass4, InstrumentCatalog.ukulele4]

        for instrument in newInstruments {
            let groups = InstrumentCatalog.tuningGroups(for: instrument)
            XCTAssertGreaterThanOrEqual(groups.count, 2, "\(instrument.name) should provide grouped presets")
            XCTAssertEqual(groups.first?.title, "Common")
        }
    }
}
