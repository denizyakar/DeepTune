import XCTest
@testable import DeepTune

final class StandardTuningMathTests: XCTestCase {
    func testStandardTuningFrequenciesMatchReference() {
        let notes = InstrumentCatalog.guitar6EStandard.notes
        XCTAssertEqual(notes.count, 6)

        XCTAssertEqual(notes[0].name, "E")
        XCTAssertEqual(notes[0].octave, 2)
        XCTAssertEqual(notes[0].frequency, 82.41, accuracy: 0.05)

        XCTAssertEqual(notes[1].name, "A")
        XCTAssertEqual(notes[1].octave, 2)
        XCTAssertEqual(notes[1].frequency, 110.0, accuracy: 0.05)

        XCTAssertEqual(notes[5].name, "E")
        XCTAssertEqual(notes[5].octave, 4)
        XCTAssertEqual(notes[5].frequency, 329.63, accuracy: 0.1)
    }

    func testDropTuningsKeepAscendingPitchOrder() {
        let tunings = [
            InstrumentCatalog.guitar6DropD,
            InstrumentCatalog.guitar6DropC,
            InstrumentCatalog.guitar6DropB,
            InstrumentCatalog.guitar6DropA
        ]

        for tuning in tunings {
            for (lhs, rhs) in zip(tuning.notes, tuning.notes.dropFirst()) {
                XCTAssertLessThan(lhs.frequency, rhs.frequency, "\(tuning.name) has non-ascending frequencies")
            }
        }
    }
}
