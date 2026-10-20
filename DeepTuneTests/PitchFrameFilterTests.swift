import XCTest
@testable import DeepTune

final class PitchFrameFilterTests: XCTestCase {
    /// Pins the filter's output for a fixed script, the way
    /// TunerCharacterizationTests pins everything after it. The rules moved out of
    /// TunerConductor unchanged, so this hash is the conductor's behaviour too.
    private static let goldenTraceHash = "afd042d3bd969005"

    private let lowE: Float = 82.407
    private let a2: Float = 110.0
    private var start: Date { Date(timeIntervalSince1970: 0) }

    private func cents(_ value: Float, from reference: Float) -> Float {
        1200 * log2(value / reference)
    }

    // MARK: - Behaviour

    func testQuietReadingsStayEmpty() {
        var filter = PitchFrameFilter()
        for frame in 0..<20 {
            let out = filter.process(pitch: a2, amp: 0.004, now: start.addingTimeInterval(Double(frame) * 0.02))
            XCTAssertEqual(out.pitch, 0, "frame \(frame)")
        }
    }

    func testGateStaysOpenBetweenItsTwoThresholds() {
        var filter = PitchFrameFilter()
        var time = start
        for _ in 0..<20 {
            time.addTimeInterval(0.02)
            _ = filter.process(pitch: a2, amp: 0.02, now: time)
        }
        // Below Manual's open threshold (0.009) but above its close threshold (0.0045).
        var last = PitchData()
        for _ in 0..<20 {
            time.addTimeInterval(0.02)
            last = filter.process(pitch: a2, amp: 0.006, now: time)
        }
        XCTAssertEqual(last.pitch, a2, accuracy: 0.001)
    }

    func testAutoIgnoresTheFirstMomentsOfAPluck() {
        var filter = PitchFrameFilter()
        filter.setTrackingTargetFrequency(a2)
        let first = filter.process(pitch: a2, amp: 0.1, now: start)
        let during = filter.process(pitch: a2, amp: 0.1, now: start.addingTimeInterval(0.04))
        let after = filter.process(pitch: a2, amp: 0.1, now: start.addingTimeInterval(0.08))
        XCTAssertEqual(first.pitch, 0)
        XCTAssertEqual(during.pitch, 0)
        XCTAssertEqual(after.pitch, a2, accuracy: 0.001)
    }

    func testAutoFoldsAnOctaveHarmonicOntoTheTarget() {
        var filter = PitchFrameFilter()
        filter.setTrackingTargetFrequency(lowE)
        _ = filter.process(pitch: lowE * 2, amp: 0.1, now: start)
        let out = filter.process(pitch: lowE * 2, amp: 0.1, now: start.addingTimeInterval(0.1))
        XCTAssertEqual(out.pitch, lowE, accuracy: 0.01)
    }

    func testAutoRejectsAReadingNothingFoldsOntoTheTarget() {
        var filter = PitchFrameFilter()
        filter.setTrackingTargetFrequency(lowE)
        _ = filter.process(pitch: 1700, amp: 0.1, now: start)
        let out = filter.process(pitch: 1700, amp: 0.1, now: start.addingTimeInterval(0.1))
        XCTAssertEqual(out.pitch, 0)
    }

    func testAutoRejectsADoublingWithin80Milliseconds() {
        var filter = PitchFrameFilter()
        filter.setTrackingTargetFrequency(a2)
        let low = a2 * pow(2, -500 / 1200)
        let high = a2 * pow(2, 500 / 1200)
        _ = filter.process(pitch: low, amp: 0.1, now: start)
        let accepted = filter.process(pitch: low, amp: 0.1, now: start.addingTimeInterval(0.07))
        XCTAssertEqual(cents(accepted.pitch, from: a2), -500, accuracy: 0.1)

        // 1000 cents up is a ratio of 1.78, inside the 1.75–2.25 the filter treats as a harmonic.
        let jump = filter.process(pitch: high, amp: 0.1, now: start.addingTimeInterval(0.12))
        XCTAssertEqual(jump.pitch, 0)

        let later = filter.process(pitch: high, amp: 0.1, now: start.addingTimeInterval(0.25))
        XCTAssertEqual(cents(later.pitch, from: a2), 500, accuracy: 0.1)
    }

    // MARK: - Trace

    func testFrameByFrameOutputIsUnchanged() {
        var filter = PitchFrameFilter()
        var trace: [String] = []
        var time = start
        var accepted = 0, empty = 0, folded = 0

        func feed(_ frames: [(pitch: Float, amp: Float)], every interval: TimeInterval) {
            for frame in frames {
                let out = filter.process(pitch: frame.pitch, amp: frame.amp, now: time)
                trace.append(String(format: "%d %.3f %.4f", trace.count, out.pitch, out.amplitude))
                if out.pitch == 0 { empty += 1 } else { accepted += 1 }
                if out.pitch > 0, abs(cents(frame.pitch, from: out.pitch)) > 1000 { folded += 1 }
                time.addTimeInterval(interval)
            }
        }

        func pluck(_ pitch: Float, frames: Int, every interval: TimeInterval) -> [(pitch: Float, amp: Float)] {
            (0..<frames).map { index in
                let t = Double(index) * interval
                let wobble = Float(sin(t * 23)) * 6 + (index % 7 == 3 ? 1200 : 0)
                return (pitch * pow(2, wobble / 1200), Float(0.09 * exp(-t * 1.6)))
            }
        }

        let silence = Array(repeating: (pitch: Float(0), amp: Float(0)), count: 10)

        // Auto on low E: device-rate and fast-rate plucks with octave errors, a reading
        // nothing folds onto, and a gate that closes and reopens.
        filter.setTrackingTargetFrequency(lowE)
        feed(silence, every: 0.085)
        feed(pluck(lowE, frames: 40, every: 0.085), every: 0.085)
        feed(pluck(lowE * pow(2, 30 / 1200), frames: 60, every: 0.02), every: 0.02)
        feed([(1700, 0.08), (1700, 0.08), (lowE, 0.08)], every: 0.02)
        feed(silence, every: 0.085)

        // Retarget, then a 1.78 ratio jump 70 ms after an accepted frame.
        filter.setTrackingTargetFrequency(a2)
        let belowA = a2 * pow(2, -500 / 1200), aboveA = a2 * pow(2, 500 / 1200)
        feed([(belowA, 0.1), (belowA, 0.1), (aboveA, 0.1), (aboveA, 0.1)], every: 0.07)

        // Manual: readings taken as they come, then a gate that closes and reopens
        // within the hold window, so the reopening frame repeats the last accepted
        // pitch, then out-of-range readings.
        filter.setTrackingTargetFrequency(nil)
        feed(silence, every: 0.02)
        feed(pluck(a2, frames: 40, every: 0.02), every: 0.02)
        feed(Array(repeating: (a2, 0), count: 8) + Array(repeating: (a2 * 1.01, 0.2), count: 3), every: 0.01)
        feed([(20, 0.05), (2000, 0.05)], every: 0.02)
        feed(pluck(a2 * 1.5, frames: 30, every: 0.085), every: 0.085)

        // Guards against a script that no longer exercises what it claims to.
        XCTAssertGreaterThan(accepted, 50)
        XCTAssertGreaterThan(empty, 20)
        XCTAssertGreaterThan(folded, 5, "Octave errors should be folded back onto the target")

        let joined = trace.joined(separator: "\n")
        let hash = Self.fnv1a64(joined)
        if hash != Self.goldenTraceHash {
            let attachment = XCTAttachment(string: joined)
            attachment.name = "pitch-filter-trace-\(hash).txt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(hash, Self.goldenTraceHash, "Filter output changed; the full trace is attached")
    }

    // Hasher is seeded per process, so a stable hash has to be computed by hand.
    private static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
