import XCTest
@testable import DeepTune

/// Measures the pitch detector on real guitar recordings and reports the
/// numbers; it fails only if the recordings cannot be read. The recordings are
/// not in the repository, so unless their folder is named this skips.
@MainActor
final class RecordingMeasurementTests: XCTestCase {
    func testMeasurePtrackOnRecordings() throws {
        guard let folder = Recording.folder else {
            throw XCTSkip("Set TEST_RUNNER_DEEPTUNE_RECORDINGS to the recordings folder to measure")
        }
        let recordings = try Recording.loadAll(from: folder)
        XCTAssertFalse(recordings.isEmpty, "No recordings in \(folder.path)")

        var lines = [RecordingMetrics.header]
        for recording in recordings {
            for mode in HarnessMode.allCases {
                var detector = PtrackDetector(sampleRate: recording.sampleRate)
                let frames = RecordingHarness.run(recording, detector: &detector, mode: mode)
                XCTAssertGreaterThan(frames.count, 50, "\(recording.name) is too short to measure")
                lines.append(RecordingMetrics(recording: recording, frames: frames, mode: mode).row)
            }
        }

        let report = lines.joined(separator: "\n")
        print("RECORDING-REPORT-BEGIN\n\(report)\nRECORDING-REPORT-END")
        let attachment = XCTAttachment(string: report)
        attachment.name = "recordings-ptrack.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
