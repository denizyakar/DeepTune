import XCTest
@testable import DeepTune

/// Measures the pitch detectors on real guitar recordings and reports the
/// numbers side by side; it fails only if the recordings cannot be read. The
/// recordings are not in the repository, so unless their folder is named this skips.
@MainActor
final class RecordingMeasurementTests: XCTestCase {
    func testCompareDetectorsOnRecordings() throws {
        guard let folder = Recording.folder else {
            throw XCTSkip("Set TEST_RUNNER_DEEPTUNE_RECORDINGS to the recordings folder to measure")
        }
        let recordings = try Recording.loadAll(from: folder)
        XCTAssertFalse(recordings.isEmpty, "No recordings in \(folder.path)")

        var metrics: [RecordingMetrics] = []
        var lagLines: [String] = []
        for recording in recordings {
            var rawByDetector: [String: [FrameRecord]] = [:]
            for mode in HarnessMode.allCases {
                var ptrack = PtrackDetector(sampleRate: recording.sampleRate)
                var yin = YINBlockDetector(sampleRate: recording.sampleRate)
                let ptrackFrames = RecordingHarness.run(recording, detector: &ptrack, mode: mode)
                let yinFrames = RecordingHarness.run(recording, detector: &yin, mode: mode)
                XCTAssertGreaterThan(ptrackFrames.count, 50, "\(recording.name) is too short to measure")
                metrics.append(RecordingMetrics(recording: recording, detector: ptrack.name, frames: ptrackFrames, mode: mode))
                metrics.append(RecordingMetrics(recording: recording, detector: yin.name, frames: yinFrames, mode: mode))
                rawByDetector = [ptrack.name: ptrackFrames, yin.name: yinFrames]
            }
            lagLines.append("\(recording.name): ptrack best matches YIN shifted by \(Self.bestLag(rawByDetector["ptrack"]!, behind: rawByDetector["yin"]!, expectedMIDI: recording.expectedMIDI)) block(s)")
        }

        var lines = [RecordingMetrics.header] + metrics.map(\.row)
        lines.append("")
        lines.append("Averages (mean over takes):")
        for pegging in [false, true] {
            for mode in HarnessMode.allCases {
                for detector in ["ptrack", "yin"] {
                    let group = metrics.filter { $0.isPeggingTake == pegging && $0.mode == mode && $0.detector == detector }
                    lines.append(Self.averageRow(group, label: "\(pegging ? "pegging" : "steady ") \(detector.padding(toLength: 6, withPad: " ", startingAt: 0)) \(mode.rawValue)"))
                }
            }
        }
        lines.append("")
        lines.append(contentsOf: lagLines)

        let report = lines.joined(separator: "\n")
        print("RECORDING-REPORT-BEGIN\n\(report)\nRECORDING-REPORT-END")
        let attachment = XCTAttachment(string: report)
        attachment.name = "recordings-ptrack-vs-yin.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func averageRow(_ group: [RecordingMetrics], label: String) -> String {
        func mean(_ values: [Double?]) -> String {
            let present = values.compactMap { $0 }
            guard !present.isEmpty else { return "     -" }
            return String(format: "%6.2f", present.reduce(0, +) / Double(present.count))
        }
        return [
            label.padding(toLength: 22, withPad: " ", startingAt: 0),
            "live% " + mean(group.map { $0.liveRate * 100 }),
            "oct% " + mean(group.map { $0.rawOctaveErrorRate * 100 }),
            "wrong% " + mean(group.map { $0.wrongNoteRate.map { $0 * 100 } }),
            "jump/100 " + mean(group.map(\.jumpsPer100)),
            "spread " + mean(group.map(\.sustainSpread)),
            "rawSprd " + mean(group.map(\.rawSustainSpread)),
            "settle " + mean(group.map(\.settleSeconds)),
        ].joined(separator: "  ")
    }

    /// How many blocks behind YIN ptrack's raw readings run: the shift that best
    /// lines the two raw pitch tracks up, over frames where both are near the string.
    private static func bestLag(_ late: [FrameRecord], behind early: [FrameRecord], expectedMIDI: Int) -> Int {
        let expected = 440 * pow(2, Float(expectedMIDI - 69) / 12)
        func cents(_ pitch: Float) -> Float? {
            guard pitch > 0 else { return nil }
            let value = 1200 * log2(pitch / expected)
            return abs(value) < 300 ? value : nil
        }
        var best = (lag: 0, error: Float.greatestFiniteMagnitude)
        for lag in 0...3 {
            var total: Float = 0
            var count = 0
            for index in early.indices where index + lag < late.count {
                guard let a = cents(early[index].raw.pitch), let b = cents(late[index + lag].raw.pitch) else { continue }
                total += abs(a - b)
                count += 1
            }
            if count > 20, total / Float(count) < best.error { best = (lag, total / Float(count)) }
        }
        return best.lag
    }
}
