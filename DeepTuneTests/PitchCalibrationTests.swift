import XCTest
@testable import DeepTune

final class PitchCalibrationTests: XCTestCase {
    func testStandardReferenceMapsA4To440() {
        let calibration = PitchCalibration.standard
        XCTAssertEqual(calibration.frequency(ofMIDI: 69), 440.0, accuracy: 1e-9)
        XCTAssertEqual(calibration.midiNumber(for: 440.0), 69.0, accuracy: 1e-9)
    }

    func testOctavesDoubleTheFrequency() {
        let calibration = PitchCalibration.standard
        XCTAssertEqual(calibration.frequency(ofMIDI: 57), 220.0, accuracy: 1e-9)
        XCTAssertEqual(calibration.frequency(ofMIDI: 81), 880.0, accuracy: 1e-9)
    }

    func testLowEString() {
        // E2 is MIDI 40.
        XCTAssertEqual(PitchCalibration.standard.frequency(ofMIDI: 40), 82.4069, accuracy: 1e-3)
    }

    func testMIDIAndFrequencyRoundTrip() {
        let calibration = PitchCalibration.standard
        for midi in 21...108 {
            let frequency = calibration.frequency(ofMIDI: midi)
            XCTAssertEqual(calibration.midiNumber(for: frequency), Double(midi), accuracy: 1e-9)
        }
    }

    func testQuarterToneRoundsToNearestNote() {
        let calibration = PitchCalibration.standard
        let slightlySharpA4 = 440.0 * pow(2.0, 40.0 / 1200.0)
        XCTAssertEqual(Int(calibration.midiNumber(for: slightlySharpA4).rounded()), 69)
        let nearlyASharp = 440.0 * pow(2.0, 60.0 / 1200.0)
        XCTAssertEqual(Int(calibration.midiNumber(for: nearlyASharp).rounded()), 70)
    }

    func testNonStandardReferenceShiftsEveryNote() {
        let calibration = PitchCalibration(referenceA4: 442.0)
        XCTAssertEqual(calibration.frequency(ofMIDI: 69), 442.0, accuracy: 1e-9)
        XCTAssertEqual(calibration.frequency(ofMIDI: 57), 221.0, accuracy: 1e-9)
        XCTAssertEqual(calibration.midiNumber(for: 442.0), 69.0, accuracy: 1e-9)
    }
}
