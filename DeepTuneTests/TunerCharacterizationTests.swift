import XCTest
@testable import DeepTune

private final class SilentConductor: TunerConductorType {
    func pitchUpdates() -> AsyncStream<PitchData> { AsyncStream { $0.finish() } }
    func start() {}
    func stop() {}
    func setTrackingTargetFrequency(_ frequency: Float?) {}
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? { nil }
    func setRecentAudioCaptureEnabled(_ enabled: Bool) {}
}

/// Pins the tuner's frame-by-frame output for a fixed script of synthetic frames.
///
/// This is a safety net for refactors that must not change behaviour: every
/// observable output is recorded after every frame and the whole trace is hashed.
/// If the hash moves, behaviour moved. When a change is *meant* to alter tuner
/// behaviour, update the golden hash in the same commit and say why.
@MainActor
final class TunerCharacterizationTests: XCTestCase {
    private static let goldenTraceHash = "4b25a7163e8928f6"

    private let frameInterval: TimeInterval = 0.02

    func testFrameByFrameOutputIsUnchanged() throws {
        let suiteName = "DeepTuneTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let session = TunerSession(
            instrument: InstrumentCatalog.guitar6,
            conductor: SilentConductor(),
            userDefaults: defaults
        )
        let auto = AutoTunerViewModel(session: session, userDefaults: defaults)
        let manual = ManualTunerViewModel(session: session)
        session.setInstrumentAndTuning(
            instrument: InstrumentCatalog.guitar6,
            tuning: InstrumentCatalog.guitar6.defaultTuning
        )
        auto.isAutoProgressEnabled = true

        var trace: [String] = []
        var now = Date(timeIntervalSince1970: 0)
        var reachedSuccess = false
        var detectedMIDIs = Set<Int>()

        func feed(_ frames: [(pitch: Float, amplitude: Float)]) {
            for frame in frames {
                session.debugInjectFrame(pitch: frame.pitch, amplitude: frame.amplitude, timestamp: now)
                now.addTimeInterval(frameInterval)
                trace.append(Self.snapshot(of: session, auto, manual, frame: trace.count))
                reachedSuccess = reachedSuccess || auto.isTuningSuccessful
                if let midi = session.detectedNote?.midiNumber { detectedMIDIs.insert(midi) }
            }
        }

        let notes = InstrumentCatalog.guitar6.defaultTuning.notes
        let lowE = Float(notes[0].frequency)

        // Auto mode, aiming at low E.
        feed(Self.silence(frames: 25))
        feed(Self.pluck(frequency: lowE, frames: 200))
        feed(Self.steady(pitch: lowE * 2, amplitude: 0.05, frames: 5))
        feed(Self.silence(frames: 60))
        feed(Self.steady(pitch: 330.0, amplitude: 0.1, frames: 20))

        // Manual mode: glide from A2 to B2 so the stabilised note has to switch.
        session.setActiveMode(.manual)
        feed(Self.glide(from: 110.0, to: 123.47, frames: 150))
        feed(Self.silence(frames: 10))
        feed(Self.steady(pitch: 220.0, amplitude: 0.1, frames: 30))

        // Back to auto on the A string, slightly flat.
        session.setActiveMode(.auto)
        auto.setTargetNote(notes[1])
        feed(Self.steady(pitch: 110.0 * pow(2.0, -15.0 / 1200.0), amplitude: 0.1, frames: 60))

        // Guards against a script that no longer exercises what it claims to.
        XCTAssertTrue(reachedSuccess, "The pluck should reach an in-tune success")
        XCTAssertGreaterThan(detectedMIDIs.count, 2, "Manual mode should report several notes")

        let joined = trace.joined(separator: "\n")
        let hash = Self.fnv1a64(joined)
        if hash != Self.goldenTraceHash {
            let attachment = XCTAttachment(string: joined)
            attachment.name = "tuner-trace-\(hash).txt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(hash, Self.goldenTraceHash, "Tuner output changed; the full trace is attached")
    }

    // MARK: - Trace

    private static func snapshot(
        of session: TunerSession,
        _ auto: AutoTunerViewModel,
        _ manual: ManualTunerViewModel,
        frame: Int
    ) -> String {
        let detected = session.detectedNote.map { "\($0.midiNumber)@\(format($0.centsFromEqualTempered))" } ?? "-"
        return [
            "\(frame)",
            "pitch=\(format(session.currentPitch))",
            "amp=\(format(session.currentAmplitude))",
            "sig=\(session.isSignalDetected)",
            "tsig=\(auto.isTargetSignalDetected)",
            "ref=\(session.hasPitchReference)",
            "auto=\(format(auto.autoCentsDistance))",
            "ok=\(auto.isTuningSuccessful)",
            "held=\(format(Float(auto.inTuneDuration)))",
            "target=\(auto.targetNote?.fullName ?? "-")",
            "done=\(auto.completedNoteIDs.count)",
            "note=\(detected)",
            "manual=\(format(manual.manualCentsDistance))",
            "lo=\(manual.manualLowestFrequency.map(format) ?? "-")",
            "hi=\(manual.manualHighestFrequency.map(format) ?? "-")",
        ].joined(separator: " ")
    }

    // Rounded so the trace survives harmless floating-point reordering, while any
    // real change in a reading still shows up.
    private static func format(_ value: Float) -> String {
        let rounded = abs(value) < 0.0005 ? 0 : value
        return String(format: "%.3f", rounded)
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

    // MARK: - Synthetic frames

    private static func silence(frames: Int) -> [(pitch: Float, amplitude: Float)] {
        Array(repeating: (pitch: 0, amplitude: 0), count: frames)
    }

    private static func steady(pitch: Float, amplitude: Float, frames: Int) -> [(pitch: Float, amplitude: Float)] {
        Array(repeating: (pitch: pitch, amplitude: amplitude), count: frames)
    }

    /// Starts 30 cents sharp and settles 2 cents sharp, with the odd dropout.
    private static func pluck(frequency: Float, frames: Int) -> [(pitch: Float, amplitude: Float)] {
        (0..<frames).map { index in
            let t = Double(index) * 0.02
            if index % 53 == 52 { return (pitch: 0, amplitude: 0) }
            let cents = 2.0 + 28.0 * exp(-t * 4.0)
            let pitch = frequency * Float(pow(2.0, cents / 1200.0))
            return (pitch: pitch, amplitude: Float(0.14 * exp(-t * 0.3)))
        }
    }

    private static func glide(from start: Float, to end: Float, frames: Int) -> [(pitch: Float, amplitude: Float)] {
        (0..<frames).map { index in
            let progress = Float(index) / Float(max(1, frames - 1))
            return (pitch: start + (end - start) * progress, amplitude: 0.1)
        }
    }
}
