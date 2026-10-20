import XCTest
@testable import DeepTune

final class YINPitchDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func makeDetector() -> YINPitchDetector {
        YINPitchDetector(configuration: .init(sampleRate: sampleRate))
    }

    /// A tone with the given harmonic amplitudes; index 0 is the fundamental.
    private func tone(_ frequency: Double, harmonics: [Double] = [1], count: Int = 4096, phase: Double = 0.3) -> [Float] {
        (0..<count).map { index in
            let t = Double(index) / sampleRate
            var value = 0.0
            for (number, amplitude) in harmonics.enumerated() where amplitude != 0 {
                value += amplitude * sin(2 * .pi * frequency * Double(number + 1) * t + phase * Double(number + 1))
            }
            return Float(0.2 * value)
        }
    }

    private func detect(_ samples: [Float]) -> YINPitchDetector.Reading {
        var detector = makeDetector()
        return samples.withUnsafeBufferPointer { detector.detect($0) }
    }

    private func cents(_ measured: Float, from expected: Double) -> Double {
        1200 * log2(Double(measured) / expected)
    }

    func testFindsPureTonesAcrossTheTunerRange() {
        // Bass low E, guitar low E, A2, high E, A4 and a high harmonic-range tone.
        for frequency in [41.20, 82.41, 110.0, 329.63, 440.0, 1000.0] {
            let reading = detect(tone(frequency))
            XCTAssertEqual(cents(reading.frequency, from: frequency), 0, accuracy: 0.5, "\(frequency) Hz")
            XCTAssertLessThan(reading.aperiodicity, 0.05, "\(frequency) Hz")
        }
    }

    func testResolvesSmallDeviations() {
        let sharp = 110.0 * pow(2, 7.0 / 1200)
        XCTAssertEqual(cents(detect(tone(sharp)).frequency, from: 110), 7, accuracy: 0.5)
        let flat = 82.41 * pow(2, -3.0 / 1200)
        XCTAssertEqual(cents(detect(tone(flat)).frequency, from: 82.41), -3, accuracy: 0.5)
    }

    func testKeepsTheFundamentalWhenHarmonicsAreLouder() {
        // A phone microphone hears a low E mostly through its harmonics.
        let weakFundamental = tone(82.41, harmonics: [0.15, 1.0, 0.7, 0.5, 0.35, 0.25, 0.15, 0.1])
        XCTAssertEqual(cents(detect(weakFundamental).frequency, from: 82.41), 0, accuracy: 1)
    }

    func testFindsTheFundamentalWhenItIsMissing() {
        let missingFundamental = tone(110, harmonics: [0, 1.0, 0.8, 0.6, 0.5])
        XCTAssertEqual(cents(detect(missingFundamental).frequency, from: 110), 0, accuracy: 1)
    }

    func testGivesNoReadingForNoiseOrSilence() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<4096).map { _ in Float.random(in: -0.2...0.2, using: &generator) }
        XCTAssertEqual(detect(noise).frequency, 0)
        XCTAssertEqual(detect([Float](repeating: 0, count: 4096)).frequency, 0)
    }

    func testGivesNoReadingForTooFewSamples() {
        let detector = makeDetector()
        let short = tone(110, count: detector.requiredSampleCount - 1)
        XCTAssertEqual(detect(short).frequency, 0)
    }

    func testReadsTheNewestSamples() {
        // An older A2 followed by a newer A3 long enough to fill the window.
        let detector = makeDetector()
        let older = tone(110, count: 6000)
        let newer = tone(220, count: detector.requiredSampleCount)
        XCTAssertEqual(cents(detect(older + newer).frequency, from: 220), 0, accuracy: 0.5)
    }
}
