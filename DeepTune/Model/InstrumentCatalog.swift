import Foundation

struct InstrumentCatalog {
    private static let referenceA4: Double = 440.0
    private static let noteOffsets: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1,
        "D": 2, "D#": 3, "Eb": 3,
        "E": 4,
        "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8,
        "A": 9, "A#": 10, "Bb": 10,
        "B": 11
    ]

    // Converts a note name + octave into an equal-tempered frequency (A4 = 440 Hz).
    private static func buildNote(_ name: String, octave: Int) -> Note {
        let semitoneInOctave = noteOffsets[name] ?? 0
        let midi = (octave + 1) * 12 + semitoneInOctave
        let frequency = referenceA4 * pow(2.0, Double(midi - 69) / 12.0)
        return Note(name: name, frequency: frequency, octave: octave)
    }

    // Keeps tuning definitions compact and easy to audit.
    private static func tuning(_ name: String, _ definition: [(String, Int)]) -> Tuning {
        Tuning(
            name: name,
            notes: definition.map { buildNote($0.0, octave: $0.1) }
        )
    }

    static let guitar6EStandard = tuning("E Standard", [("E", 2), ("A", 2), ("D", 3), ("G", 3), ("B", 3), ("E", 4)])
    static let guitar6EbStandard = tuning("Eb Standard", [("Eb", 2), ("Ab", 2), ("Db", 3), ("Gb", 3), ("Bb", 3), ("Eb", 4)])
    static let guitar6DStandard = tuning("D Standard", [("D", 2), ("G", 2), ("C", 3), ("F", 3), ("A", 3), ("D", 4)])
    static let guitar6CSharpStandard = tuning("C# Standard", [("C#", 2), ("F#", 2), ("B", 2), ("E", 3), ("G#", 3), ("C#", 4)])
    static let guitar6CStandard = tuning("C Standard", [("C", 2), ("F", 2), ("Bb", 2), ("Eb", 3), ("G", 3), ("C", 4)])

    static let guitar6DropD = tuning("Drop D", [("D", 2), ("A", 2), ("D", 3), ("G", 3), ("B", 3), ("E", 4)])
    static let guitar6DropCSharp = tuning("Drop C#", [("C#", 2), ("G#", 2), ("C#", 3), ("F#", 3), ("A#", 3), ("D#", 4)])
    static let guitar6DropC = tuning("Drop C", [("C", 2), ("G", 2), ("C", 3), ("F", 3), ("A", 3), ("D", 4)])

    static let guitar6BStandard = tuning("B Standard", [("B", 1), ("E", 2), ("A", 2), ("D", 3), ("F#", 3), ("B", 3)])
    static let guitar6DropB = tuning("Drop B", [("B", 1), ("F#", 2), ("B", 2), ("E", 3), ("G#", 3), ("C#", 4)])
    static let guitar6DropA = tuning("Drop A", [("A", 1), ("E", 2), ("A", 2), ("D", 3), ("F#", 3), ("B", 3)])

    static let guitar6DropGSharp = tuning("Drop G#", [("G#", 1), ("D#", 2), ("G#", 2), ("C#", 3), ("F#", 3), ("A#", 3)])
    static let guitar6DropG = tuning("Drop G", [("G", 1), ("D", 2), ("G", 2), ("C", 3), ("F", 3), ("A", 3)])
    static let guitar6DropFSharp = tuning("Drop F#", [("F#", 1), ("C#", 2), ("F#", 2), ("B", 2), ("E", 3), ("G#", 3)])

    static let guitar6FACGCE = tuning("FACGCE", [("F", 2), ("A", 2), ("C", 3), ("G", 3), ("C", 4), ("E", 4)])
    static let guitar6DAEACSharpE = tuning("DAEAC#E", [("D", 2), ("A", 2), ("E", 3), ("A", 3), ("C#", 4), ("E", 4)])
    static let guitar6CGCGCE = tuning("CGCGCE", [("C", 2), ("G", 2), ("C", 3), ("G", 3), ("C", 4), ("E", 4)])
    static let guitar6OpenD = tuning("Open D", [("D", 2), ("A", 2), ("D", 3), ("F#", 3), ("A", 3), ("D", 4)])
    static let guitar6OpenG = tuning("Open G", [("D", 2), ("G", 2), ("D", 3), ("G", 3), ("B", 3), ("D", 4)])
    static let guitar6OpenE = tuning("Open E", [("E", 2), ("B", 2), ("E", 3), ("G#", 3), ("B", 3), ("E", 4)])
    static let guitar6DADGAD = tuning("DADGAD", [("D", 2), ("A", 2), ("D", 3), ("G", 3), ("A", 3), ("D", 4)])

    static let guitar6TuningGroups: [TuningGroup] = [
        TuningGroup(
            title: "Common",
            subtitle: "Everyday rock, metal, alternative and cover workflows",
            tunings: [
                guitar6EStandard,
                guitar6EbStandard,
                guitar6DStandard,
                guitar6CSharpStandard,
                guitar6CStandard,
                guitar6DropD,
                guitar6DropCSharp,
                guitar6DropC,
                guitar6BStandard,
                guitar6DropB,
                guitar6DropA
            ]
        ),
        TuningGroup(
            title: "Heavy Drops",
            subtitle: "Requires heavier gauge strings and setup awareness",
            tunings: [
                guitar6DropGSharp,
                guitar6DropG,
                guitar6DropFSharp
            ]
        ),
        TuningGroup(
            title: "Niche / Genre",
            subtitle: "Midwest emo, alt, shoegaze and math-inspired tunings",
            tunings: [
                guitar6FACGCE,
                guitar6DAEACSharpE,
                guitar6CGCGCE
            ]
        ),
        TuningGroup(
            title: "Roots / Slide",
            subtitle: "Blues, country, folk and celtic-leaning open tunings",
            tunings: [
                guitar6OpenD,
                guitar6OpenG,
                guitar6OpenE,
                guitar6DADGAD
            ]
        )
    ]

    static func tuningGroups(for instrument: Instrument) -> [TuningGroup] {
        switch instrument.type {
        case .guitar6:
            return guitar6TuningGroups
        case .guitar7, .guitar8, .bass, .ukulele:
            return [
                TuningGroup(
                    title: "Available",
                    subtitle: nil,
                    tunings: instrument.availableTunings
                )
            ]
        }
    }

    private static let guitar6AllTunings = guitar6TuningGroups.flatMap(\.tunings)

    static let guitar6 = Instrument(
        type: .guitar6,
        defaultTuning: guitar6EStandard,
        availableTunings: guitar6AllTunings
    )

    static let allInstruments: [Instrument] = [guitar6]
}
