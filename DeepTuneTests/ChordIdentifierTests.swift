import XCTest
@testable import DeepTune

/// Characterisation tests: these lock in what the fallback identifier does today,
/// so the behaviour round can change it deliberately rather than by accident.
final class ChordIdentifierTests: XCTestCase {
    // Pitch classes, for readability: 0 = C ... 11 = B.
    private let c = 0, cSharp = 1, d = 2, dSharp = 3, e = 4, f = 5
    private let fSharp = 6, g = 7, gSharp = 8, a = 9, aSharp = 10, b = 11

    private func evenCounts(_ pitchClasses: [Int], each weight: Int = 3) -> [Int: Int] {
        pitchClasses.reduce(into: [Int: Int]()) { $0[$1] = weight }
    }

    // MARK: - Chords it should name

    func testIdentifiesMajorTriad() {
        let result = ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g]))

        XCTAssertEqual(result?.name, "C")
        XCTAssertEqual(result?.rootName, "C")
        XCTAssertEqual(result?.observedNoteNames, ["C", "E", "G"])
    }

    func testIdentifiesMinorTriad() {
        let result = ChordIdentifier.identify(pitchClassCounts: evenCounts([c, dSharp, g]))

        XCTAssertEqual(result?.name, "Cm")
        XCTAssertEqual(result?.rootName, "C")
    }

    func testIdentifiesDominantSeventh() {
        let result = ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g, aSharp]))

        XCTAssertEqual(result?.name, "C7")
    }

    func testIdentifiesPowerChordFromTwoNotes() {
        // Two-note input is allowed only when the winning template itself has two notes.
        let result = ChordIdentifier.identify(pitchClassCounts: evenCounts([c, g]))

        XCTAssertEqual(result?.name, "C5")
    }

    // MARK: - Ties the ambiguity guard refuses to break

    func testRefusesSuspendedChordsBecauseTheirTemplatesTie() {
        // Csus4 and Fsus2 are the same three pitch classes, so both templates score
        // identically and the ambiguity guard rejects the tie. A consequence of the
        // current design: the fallback can never name a suspended chord.
        XCTAssertNil(ChordIdentifier.identify(pitchClassCounts: evenCounts([c, f, g])))
    }

    // MARK: - Genuinely ambiguous input

    func testPrefersTheTemplateThatExplainsEveryHeardNote() {
        // C-E-G-A is both C6 and Am7. C6 is not in the fallback's template set, and
        // Am7 covers all four notes while C leaves the A unexplained, so Am7 wins.
        let result = ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g, a]))

        XCTAssertEqual(result?.name, "Am7")
        XCTAssertEqual(result?.rootName, "A")
    }

    func testRanksAlternativesBehindTheBestMatch() throws {
        let result = try XCTUnwrap(ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g])))

        XCTAssertEqual(result.candidates.first?.name, result.name)
        XCTAssertGreaterThan(result.candidates.count, 1)

        let confidences = result.candidates.map(\.confidence)
        XCTAssertEqual(confidences, confidences.sorted(by: >), "candidates should be ranked")
    }

    // MARK: - Cases it should refuse

    func testReturnsNilForNoInput() {
        XCTAssertNil(ChordIdentifier.identify(pitchClassCounts: [:]))
    }

    func testReturnsNilForASingleNote() {
        XCTAssertNil(ChordIdentifier.identify(pitchClassCounts: [c: 5]))
    }

    func testReturnsNilWhenTwoNotesOnlyFitAThreeNoteTemplate() {
        // A bare major third has no two-note template to match, and guessing the
        // missing fifth would be inventing evidence.
        XCTAssertNil(ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e])))
    }

    // MARK: - Confidence

    func testConfidenceStaysWithinItsBounds() throws {
        let clean = try XCTUnwrap(ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g])))
        XCTAssertLessThanOrEqual(clean.confidence, 0.82, "0.82 is the ceiling the scoring caps at")
        XCTAssertGreaterThanOrEqual(clean.confidence, 0.26, "0.26 is the floor below which it returns nil")
    }

    func testUnrelatedExtraNoteLowersConfidence() throws {
        let clean = try XCTUnwrap(ChordIdentifier.identify(pitchClassCounts: evenCounts([c, e, g])))

        var muddied = evenCounts([c, e, g])
        muddied[cSharp] = 2 // a note that belongs to no reading of this chord
        let noisy = ChordIdentifier.identify(pitchClassCounts: muddied)

        if let noisy {
            XCTAssertLessThan(noisy.confidence, clean.confidence)
        }
    }

    // MARK: - Observed notes

    func testObservedNoteNamesDropNegligibleWeights() {
        var counts = evenCounts([c, e, g], each: 100)
        counts[b] = 1 // far below the 16% relative threshold

        XCTAssertEqual(ChordIdentifier.observedNoteNames(pitchClassCounts: counts), ["C", "E", "G"])
    }
}
