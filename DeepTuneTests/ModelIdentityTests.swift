import XCTest
@testable import DeepTune

/// Identity is derived from content, so these ids have to stay unique within the
/// scope where they are used: ForEach rows, the completed-string set, persistence.
@MainActor
final class ModelIdentityTests: XCTestCase {
    func testInstrumentIDsAreUnique() {
        assertUnique(InstrumentCatalog.allInstruments.map(\.id), "instruments")
    }

    func testTuningIDsAreUniqueWithinAnInstrument() {
        for instrument in InstrumentCatalog.allInstruments {
            assertUnique(instrument.availableTunings.map(\.id), "\(instrument.name) tunings")
        }
    }

    func testTuningGroupIDsAreUniqueWithinAnInstrument() {
        for instrument in InstrumentCatalog.allInstruments {
            let groups = InstrumentCatalog.tuningGroups(for: instrument)
            assertUnique(groups.map(\.id), "\(instrument.name) groups")
            for group in groups {
                assertUnique(group.tunings.map(\.id), "\(instrument.name) / \(group.title)")
            }
        }
    }

    func testNoteIDsAreUniqueWithinATuning() {
        for instrument in InstrumentCatalog.allInstruments {
            for tuning in instrument.availableTunings {
                assertUnique(tuning.notes.map(\.id), "\(instrument.name) / \(tuning.name)")
            }
        }
    }

    func testIndependentlyBuiltEqualValuesAreEqual() {
        let a = Note(name: "E", frequency: 82.41, octave: 2)
        let b = Note(name: "E", frequency: 82.41, octave: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, b.id)

        let tuningA = Tuning(name: "Test", notes: [a])
        let tuningB = Tuning(name: "Test", notes: [b])
        XCTAssertEqual(tuningA, tuningB)
    }

    private func assertUnique<ID: Hashable>(_ ids: [ID], _ scope: String, line: UInt = #line) {
        var seen = Set<ID>()
        let duplicates = ids.filter { !seen.insert($0).inserted }
        XCTAssertTrue(duplicates.isEmpty, "Duplicate ids in \(scope): \(duplicates)", line: line)
    }
}
