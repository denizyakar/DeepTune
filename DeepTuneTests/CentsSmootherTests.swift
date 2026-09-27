import XCTest
@testable import DeepTune

final class CentsSmootherTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    /// Feeds a constant reading at `rate` for `duration` seconds and returns the meter value.
    private func settle(on cents: Float, rate: Double, duration: TimeInterval) -> Float {
        var smoother = CentsSmoother()
        let dt = 1 / rate
        var elapsed: TimeInterval = 0
        var time = start
        while elapsed < duration {
            time.addTimeInterval(dt)
            elapsed += dt
            smoother.add(cents, at: time, elapsed: dt)
        }
        return smoother.value
    }

    func testSettlingDoesNotDependOnFrameRate() {
        for duration in [0.25, 0.5, 1.0] {
            let phone = settle(on: 40, rate: 11.7, duration: duration)
            let fast = settle(on: 40, rate: 60, duration: duration)
            XCTAssertEqual(phone, fast, accuracy: 4, "after \(duration) s")
        }
    }

    func testReachesTheReading() {
        XCTAssertEqual(settle(on: 12, rate: 11.7, duration: 2), 12, accuracy: 0.1)
    }

    func testSingleSpikeBarelyMovesTheMeter() {
        var smoother = CentsSmoother()
        let dt = 1 / 11.7
        var time = start
        for _ in 0..<12 {
            time.addTimeInterval(dt)
            smoother.add(0, at: time, elapsed: dt)
        }
        time.addTimeInterval(dt)
        smoother.add(95, at: time, elapsed: dt)
        XCTAssertLessThan(abs(smoother.value), 1, "one harmonic spike should be trimmed away")
    }

    func testResetKeepsTheNeedleWhereItIs() {
        var smoother = CentsSmoother()
        let dt = 1 / 11.7
        var time = start
        for _ in 0..<30 {
            time.addTimeInterval(dt)
            smoother.add(20, at: time, elapsed: dt)
        }
        let before = smoother.value
        smoother.reset()
        XCTAssertEqual(smoother.value, before)
        XCTAssertFalse(smoother.hasSamples)

        smoother.reset(to: -5)
        XCTAssertEqual(smoother.value, -5)
    }

    func testTrimmedMeanDropsTheExtremes() {
        XCTAssertEqual(CentsSmoother.trimmedMean(of: [-10, 9, -6, 95, 8]) ?? .nan, (-6 + 8 + 9) / 3, accuracy: 0.001)
        XCTAssertEqual(CentsSmoother.trimmedMean(of: [3, 5]) ?? .nan, 4, accuracy: 0.001)
        XCTAssertNil(CentsSmoother.trimmedMean(of: []))
    }
}
