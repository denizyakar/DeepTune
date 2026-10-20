import AVFoundation
import CSoundpipeAudioKit
import Foundation
@testable import DeepTune

/// Turns one block of microphone samples into a reading, the way PitchTap
/// analyses each tap buffer.
protocol BlockPitchDetector {
    var name: String { get }
    mutating func analyze(_ block: inout [Float]) -> PitchData
}

/// PitchTap without the tap: the same Soundpipe ptrack tracker, created with
/// the parameters PitchTap uses and fed the same 4096-sample blocks.
final class PtrackDetector: BlockPitchDetector {
    let name = "ptrack"
    private let tracker: PitchTrackerRef

    init(sampleRate: Double) {
        tracker = akPitchTrackerCreate(UInt32(sampleRate), 4096, 20)
    }

    deinit {
        akPitchTrackerDestroy(tracker)
    }

    func analyze(_ block: inout [Float]) -> PitchData {
        block.withUnsafeMutableBufferPointer {
            akPitchTrackerAnalyze(tracker, $0.baseAddress, UInt32($0.count))
        }
        var amplitude: Float = 0
        var pitch: Float = 0
        akPitchTrackerGetResults(tracker, &amplitude, &pitch)
        return PitchData(pitch: pitch, amplitude: amplitude)
    }
}

/// YIN fed the same blocks. The signal gate's thresholds were tuned on
/// ptrack's level, so YIN's level is put on that scale: on the recordings,
/// ptrack's level is 2.53·rms^0.757 of the block (R² 0.95). The fit only
/// holds against the block *before* the one ptrack was just given, because
/// ptrack reports each reading one block late.
struct YINBlockDetector: BlockPitchDetector {
    let name = "yin"
    private var detector: YINPitchDetector
    private var history: [Float] = []

    init(sampleRate: Double) {
        detector = YINPitchDetector(configuration: .init(sampleRate: sampleRate))
    }

    static func ptrackScaleLevel(rms: Float) -> Float {
        rms > 0 ? 2.53 * pow(rms, 0.757) : 0
    }

    mutating func analyze(_ block: inout [Float]) -> PitchData {
        history.append(contentsOf: block)
        let required = detector.requiredSampleCount
        if history.count > required {
            history.removeFirst(history.count - required)
        }
        let reading = history.withUnsafeBufferPointer { detector.detect($0) }
        let rms = sqrt(block.reduce(0) { $0 + $1 * $1 } / Float(max(1, block.count)))
        return PitchData(pitch: reading.frequency, amplitude: Self.ptrackScaleLevel(rms: rms))
    }
}

/// One take of one open string, read from the recordings folder.
struct Recording {
    /// The folder the take came from: one folder per way of playing.
    let take: String
    let string: String
    let expectedMIDI: Int
    let samples: [Float]
    let sampleRate: Double

    var name: String { "\(take)/\(string)" }

    private static let openStrings = ["e2": 40, "a2": 45, "d3": 50, "g3": 55, "b3": 59, "e4": 64]

    /// The recordings are the user's own and stay out of the public repo, so the
    /// folder is only ever named explicitly: run with
    /// `TEST_RUNNER_DEEPTUNE_RECORDINGS=<folder> xcodebuild test`. There is no
    /// default, because guessing a path under ~/Documents makes macOS hold the
    /// test on a privacy prompt and the whole suite stalls.
    static var folder: URL? {
        ProcessInfo.processInfo.environment["DEEPTUNE_RECORDINGS"].map { URL(fileURLWithPath: $0) }
    }

    static func loadAll(from folder: URL) throws -> [Recording] {
        let manager = FileManager.default
        let takes = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try takes.flatMap { take in
            try manager.contentsOfDirectory(at: take, includingPropertiesForKeys: nil)
                .filter { ["m4a", "wav", "caf"].contains($0.pathExtension.lowercased()) }
                .compactMap { url -> Recording? in
                    let string = url.deletingPathExtension().lastPathComponent.lowercased()
                    guard let midi = openStrings[string] else { return nil }
                    return try load(url, take: take.lastPathComponent, string: string, midi: midi)
                }
                .sorted { $0.expectedMIDI < $1.expectedMIDI }
        }
    }

    private static func load(_ url: URL, take: String, string: String, midi: Int) throws -> Recording {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return Recording(take: take, string: string, expectedMIDI: midi, samples: samples, sampleRate: format.sampleRate)
    }
}

/// What the tuner did with one block.
struct FrameRecord {
    let time: Double
    let blockRMS: Float
    let raw: PitchData
    let filtered: PitchData
    /// Where the needle is drawn, and whether the screen calls it a live reading
    /// rather than showing NO SIGNAL.
    let needleCents: Float
    let isLive: Bool
    /// The note the screen names; Manual only.
    let noteMIDI: Int?
}

enum HarnessMode: String, CaseIterable {
    case auto
    case manual
}

/// Plays a recording into the live chain: detector, PitchFrameFilter,
/// TunerSession and the mode's view model, block by block, with block-accurate
/// timestamps instead of the wall clock.
@MainActor
enum RecordingHarness {
    static let blockSize = 4096

    static func run(_ recording: Recording, detector: inout some BlockPitchDetector, mode: HarnessMode) -> [FrameRecord] {
        let suiteName = "DeepTuneTests.Recordings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let instrument = InstrumentCatalog.guitar6
        let session = TunerSession(instrument: instrument, conductor: SilentConductor(), userDefaults: defaults)
        let auto = AutoTunerViewModel(session: session, userDefaults: defaults)
        let manual = ManualTunerViewModel(session: session)
        var filter = PitchFrameFilter()

        switch mode {
        case .auto:
            session.setActiveMode(.auto)
            let target = instrument.defaultTuning.notes.first { midi(of: $0.frequency) == recording.expectedMIDI }
            if let target {
                auto.setTargetNote(target)
                filter.setTrackingTargetFrequency(Float(target.frequency))
            }
        case .manual:
            session.setActiveMode(.manual)
            filter.setTrackingTargetFrequency(nil)
        }

        var records: [FrameRecord] = []
        var block = [Float](repeating: 0, count: blockSize)
        var start = 0
        while start + blockSize <= recording.samples.count {
            block.withUnsafeMutableBufferPointer { destination in
                recording.samples.withUnsafeBufferPointer { source in
                    destination.baseAddress!.update(from: source.baseAddress! + start, count: blockSize)
                }
            }
            let rms = sqrt(block.reduce(0) { $0 + $1 * $1 } / Float(blockSize))
            // A reading describes the block that has just finished arriving.
            let time = Double(start + blockSize) / recording.sampleRate
            let now = Date(timeIntervalSince1970: time)

            let raw = detector.analyze(&block)
            let filtered = filter.process(pitch: raw.pitch, amp: raw.amplitude, now: now)
            session.debugInjectFrame(pitch: filtered.pitch, amplitude: filtered.amplitude, timestamp: now)

            switch mode {
            case .auto:
                records.append(FrameRecord(
                    time: time, blockRMS: rms, raw: raw, filtered: filtered,
                    needleCents: auto.autoCentsDistance,
                    isLive: auto.isTargetSignalDetected,
                    noteMIDI: nil
                ))
            case .manual:
                records.append(FrameRecord(
                    time: time, blockRMS: rms, raw: raw, filtered: filtered,
                    needleCents: manual.manualCentsDistance,
                    isLive: session.isSignalDetected,
                    noteMIDI: session.detectedNote?.midiNumber
                ))
            }
            start += blockSize
        }
        return records
    }

    nonisolated static func midi(of frequency: Double) -> Int {
        Int((69 + 12 * log2(frequency / 440)).rounded())
    }
}
