import Foundation

/// Equal-tempered pitch math against a single concert-pitch reference.
/// Everything that converts between notes and frequencies goes through here,
/// so the reference is defined once.
nonisolated struct PitchCalibration: Equatable, Sendable {
    static let standard = PitchCalibration(referenceA4: 440.0)

    private static let a4MIDINumber = 69

    let referenceA4: Double

    func frequency(ofMIDI midi: Int) -> Double {
        referenceA4 * pow(2.0, Double(midi - Self.a4MIDINumber) / 12.0)
    }

    /// Fractional MIDI number; round it to get the nearest note.
    func midiNumber(for frequency: Double) -> Double {
        Double(Self.a4MIDINumber) + 12.0 * log2(frequency / referenceA4)
    }
}
