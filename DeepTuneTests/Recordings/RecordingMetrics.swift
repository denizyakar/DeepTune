import Foundation
@testable import DeepTune

/// What a recording says about a detector, without knowing the true pitch.
///
/// Every measure is something a good tuner shows regardless of how well the
/// guitar was tuned: a reading while the string rings, the right string, a
/// steady needle while the pitch is steady, and no jumps while the peg turns,
/// because a turning peg moves the pitch a cent or two per frame at most.
struct RecordingMetrics {
    let recording: String
    let detector: String
    let isPeggingTake: Bool
    let mode: HarnessMode
    /// Blocks within 30 dB of the take's loudest block: the string is ringing.
    let ringingFrames: Int
    /// Ringing frames the screen shows as a live reading rather than NO SIGNAL.
    let liveRate: Double
    /// Ringing frames with no detector reading at all.
    let rawDropoutRate: Double
    /// Ringing frames the detector places more than half an octave from the string.
    let rawOctaveErrorRate: Double
    /// Live ringing frames naming the wrong note (Manual). A turning peg may
    /// legitimately reach the neighbouring note, so pegging takes allow one semitone.
    let wrongNoteRate: Double?
    /// Needle moves of more than 5 cents in one frame, per 100 live ringing frames.
    let jumpsPer100: Double
    /// Steady takes: median over plucks of the needle's spread (standard
    /// deviation, cents) from half a second after the pluck.
    let sustainSpread: Double?
    /// The same for the detector's own reading, octave errors left out.
    let rawSustainSpread: Double?
    /// Steady takes: median time from the pluck until the needle stays within
    /// ±3 cents of where it ends up for four frames, and how many plucks got there.
    let settleSeconds: Double?
    let settledPlucks: (settled: Int, total: Int)?

    static let jumpThresholdCents: Float = 5
    private static let ringingWindowDecibels: Float = 30
    private static let octaveErrorCents: Float = 600

    init(recording: Recording, detector: String, frames: [FrameRecord], mode: HarnessMode) {
        self.recording = recording.name
        self.detector = detector
        self.mode = mode
        let isPeggingTake = recording.take.contains("burgu")
        self.isPeggingTake = isPeggingTake
        let expectedFrequency = Float(440 * pow(2, Double(recording.expectedMIDI - 69) / 12))
        func rawCents(_ frame: FrameRecord) -> Float {
            1200 * log2(frame.raw.pitch / expectedFrequency)
        }

        let loudest = frames.map(\.blockRMS).max() ?? 0
        let ringingFloor = loudest * pow(10, -Self.ringingWindowDecibels / 20)
        let ringing = frames.map { $0.blockRMS >= ringingFloor }
        let ringingIndices = frames.indices.filter { ringing[$0] }
        ringingFrames = ringingIndices.count
        let count = Double(max(1, ringingIndices.count))

        liveRate = Double(ringingIndices.filter { frames[$0].isLive }.count) / count
        rawDropoutRate = Double(ringingIndices.filter { frames[$0].raw.pitch <= 0 }.count) / count
        rawOctaveErrorRate = Double(ringingIndices.filter {
            frames[$0].raw.pitch > 0 && abs(rawCents(frames[$0])) > Self.octaveErrorCents
        }.count) / count

        if mode == .manual {
            let named = ringingIndices.filter { frames[$0].isLive && frames[$0].noteMIDI != nil }
            let tolerance = isPeggingTake ? 1 : 0
            let wrong = named.filter { abs(frames[$0].noteMIDI! - recording.expectedMIDI) > tolerance }
            wrongNoteRate = Double(wrong.count) / Double(max(1, named.count))
        } else {
            wrongNoteRate = nil
        }

        var jumps = 0
        var liveSteps = 0
        for index in frames.indices.dropFirst() where ringing[index] && ringing[index - 1] {
            guard frames[index].isLive, frames[index - 1].isLive else { continue }
            liveSteps += 1
            if abs(frames[index].needleCents - frames[index - 1].needleCents) > Self.jumpThresholdCents {
                jumps += 1
            }
        }
        jumpsPer100 = 100 * Double(jumps) / Double(max(1, liveSteps))

        guard !isPeggingTake else {
            sustainSpread = nil
            rawSustainSpread = nil
            settleSeconds = nil
            settledPlucks = nil
            return
        }

        // A pluck is a ringing block at least 1.8x louder than the one before,
        // half a second clear of the previous pluck.
        var onsets: [Int] = []
        for index in frames.indices.dropFirst() where ringing[index] {
            let louder = frames[index].blockRMS > 1.8 * frames[index - 1].blockRMS
            let clear = onsets.last.map { frames[index].time - frames[$0].time >= 0.5 } ?? true
            if louder && clear { onsets.append(index) }
        }

        var spreads: [Double] = []
        var rawSpreads: [Double] = []
        var settleTimes: [Double] = []
        for (pluck, onset) in onsets.enumerated() {
            let end = pluck + 1 < onsets.count ? onsets[pluck + 1] : frames.count
            let segment = (onset..<end).filter { ringing[$0] }
            let sustain = segment.filter { frames[$0].time - frames[onset].time >= 0.5 && frames[$0].isLive }
            guard sustain.count >= 4 else { continue }

            let needle = sustain.map { Double(frames[$0].needleCents) }
            spreads.append(Self.standardDeviation(needle))
            let raw = sustain.filter { frames[$0].raw.pitch > 0 }.map { Double(rawCents(frames[$0])) }
                .filter { abs($0) <= Double(Self.octaveErrorCents) }
            if raw.count >= 4 { rawSpreads.append(Self.standardDeviation(raw)) }

            let settled = Self.median(needle)
            let window = 4
            if let first = segment.indices.first(where: { position in
                guard position + window <= segment.count else { return false }
                return segment[position..<(position + window)].allSatisfy {
                    frames[$0].isLive && abs(Double(frames[$0].needleCents) - settled) <= 3
                }
            }) {
                settleTimes.append(frames[segment[first]].time - frames[onset].time)
            }
        }
        sustainSpread = spreads.isEmpty ? nil : Self.median(spreads)
        rawSustainSpread = rawSpreads.isEmpty ? nil : Self.median(rawSpreads)
        settleSeconds = settleTimes.isEmpty ? nil : Self.median(settleTimes)
        settledPlucks = (settleTimes.count, onsets.count)
    }

    static let header = [
        "recording".padding(toLength: 30, withPad: " ", startingAt: 0),
        "detect", "mode  ", "ring", "live%", "drop%", "oct%", "wrong%", "jump/100", "spread", "rawSprd", "settle", "settled",
    ].joined(separator: " ")

    var row: String {
        func percent(_ value: Double?) -> String { value.map { String(format: "%5.1f", $0 * 100) } ?? "    -" }
        func number(_ value: Double?, _ format: String) -> String { value.map { String(format: format, $0) } ?? "     -" }
        return [
            recording.padding(toLength: 30, withPad: " ", startingAt: 0),
            detector.padding(toLength: 6, withPad: " ", startingAt: 0),
            mode.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0),
            String(format: "%4d", ringingFrames),
            percent(liveRate), percent(rawDropoutRate), percent(rawOctaveErrorRate), percent(wrongNoteRate) + " ",
            String(format: "%8.1f", jumpsPer100),
            number(sustainSpread, "%6.2f"), number(rawSustainSpread, "%7.2f"), number(settleSeconds, "%5.2fs"),
            settledPlucks.map { "\($0.settled)/\($0.total)" } ?? "-",
        ].joined(separator: " ")
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count))
    }
}
