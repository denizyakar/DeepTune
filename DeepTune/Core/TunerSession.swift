import Foundation
import Observation

struct DetectedNote: Equatable {
    let name: String
    let octave: Int
    let midiNumber: Int
    let nearestFrequency: Float
    let centsFromEqualTempered: Float
}

struct AudioSampleWindow {
    let samples: [Float]
    let sampleRate: Double
}

enum TunerMode: Hashable {
    case auto
    case manual
}

/// One audio frame after the shared front-end has read it.
enum PitchFrame {
    /// No usable pitch. `isWithinHoldWindow` stays true for a moment after the last
    /// live frame, so readings can linger instead of snapping away.
    case silent(isWithinHoldWindow: Bool, frameDelta: TimeInterval, now: Date)
    /// `pitch` is smoothed; `note` is the nearest note after stabilisation.
    case live(pitch: Float, note: DetectedNote, frameDelta: TimeInterval, now: Date)
}

enum TunerSessionEvent {
    case frame(PitchFrame)
    case modeChanged(TunerMode)
    case selectionChanged(Tuning)
}

/// The part of the tuner every screen shares: the audio engine, the selected
/// instrument and tuning, and the per-frame reading of the raw pitch.
///
/// Screen view models subscribe to its events. Delivery is synchronous and in
/// subscription order, so every screen sees each frame before the next arrives.
@Observable
final class TunerSession {
    private enum PersistenceKey {
        static let instrumentType = "DeepTune.selectedInstrumentType"
        static let tuningSignature = "DeepTune.selectedTuningSignature"
    }

    private(set) var currentInstrument: Instrument
    private(set) var currentTuning: Tuning
    private(set) var activeMode: TunerMode = .auto

    // Raw values coming from the audio layer.
    private(set) var currentPitch: Float = 0.0
    private(set) var currentAmplitude: Float = 0.0
    private(set) var isSignalDetected = false
    private(set) var hasPitchReference = false
    /// The nearest note to the smoothed pitch, held steady across brief flickers.
    private(set) var detectedNote: DetectedNote?

    private let conductor: TunerConductorType
    private let userDefaults: UserDefaults
    @ObservationIgnored private var eventHandlers: [(TunerSessionEvent) -> Void] = []

    private let calibration = PitchCalibration.standard
    private let pitchSmoothingFactor: Float = 0.2
    private let signalHoldDuration: TimeInterval = 1.0
    private let noteSwitchRequiredFrames = 4

    private var smoothedPitch: Float = 0.0
    private var lastProcessFrameAt: Date?
    private var lastLiveSignalAt: Date?
    private var stableMIDI: Int?
    private var candidateMIDI: Int?
    private var candidateStreak = 0
    // Read from deinit, which can't go through observation-tracked accessors.
    @ObservationIgnored private var isConductorRunning = false

    init(
        instrument: Instrument = InstrumentCatalog.guitar6,
        conductor: TunerConductorType = TunerConductor(),
        userDefaults: UserDefaults = .standard
    ) {
        self.conductor = conductor
        self.userDefaults = userDefaults
        let restoredInstrument = Self.restoreInstrument(from: userDefaults) ?? instrument
        self.currentInstrument = restoredInstrument
        self.currentTuning = Self.restoreTuning(for: restoredInstrument, from: userDefaults)
            ?? restoredInstrument.defaultTuning
        persistSelection()
    }

    deinit {
        if isConductorRunning {
            conductor.stop()
        }
    }

    func subscribe(_ handler: @escaping (TunerSessionEvent) -> Void) {
        eventHandlers.append(handler)
    }

    // MARK: - Audio

    /// Feeds conductor frames through the tuner until the calling task is cancelled.
    /// Driven by the view's `task()`, so the loop ends with the screen.
    func processPitchUpdates() async {
        for await data in conductor.pitchUpdates() {
            processAudioData(pitch: data.pitch, amplitude: data.amplitude, now: Date())
        }
    }

    func start() {
        guard !isConductorRunning else { return }
        conductor.start()
        isConductorRunning = true
    }

    func stop() {
        guard isConductorRunning else { return }
        conductor.stop()
        isConductorRunning = false
    }

    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? {
        conductor.recentAudioWindow(duration: duration)
    }

    func setRecentAudioCaptureEnabled(_ enabled: Bool) {
        conductor.setRecentAudioCaptureEnabled(enabled)
    }

    func setTrackingTargetFrequency(_ frequency: Float?) {
        conductor.setTrackingTargetFrequency(frequency)
    }

    // MARK: - Selection and mode

    func setInstrumentAndTuning(instrument: Instrument, tuning: Tuning) {
        currentInstrument = instrument
        currentTuning = tuning
        publish(.selectionChanged(tuning))
        persistSelection()
    }

    func setInstrument(_ instrument: Instrument) {
        if currentInstrument == instrument {
            return
        }
        setInstrumentAndTuning(instrument: instrument, tuning: instrument.defaultTuning)
    }

    func setActiveMode(_ mode: TunerMode) {
        activeMode = mode
        publish(.modeChanged(mode))
    }

    // MARK: - Frame processing

    private func processAudioData(pitch: Float, amplitude: Float, now: Date) {
        currentPitch = pitch
        currentAmplitude = amplitude

        let frameDelta = max(0.0, min(0.2, now.timeIntervalSince(lastProcessFrameAt ?? now)))
        lastProcessFrameAt = now

        guard pitch > 0, amplitude > 0 else {
            let isWithinHoldWindow: Bool
            if let lastLiveSignalAt {
                isWithinHoldWindow = now.timeIntervalSince(lastLiveSignalAt) <= signalHoldDuration
            } else {
                isWithinHoldWindow = false
            }

            isSignalDetected = isWithinHoldWindow
            publish(.frame(.silent(isWithinHoldWindow: isWithinHoldWindow, frameDelta: frameDelta, now: now)))
            return
        }

        isSignalDetected = true
        hasPitchReference = true
        lastLiveSignalAt = now
        smoothedPitch = smoothedPitch == 0 ? pitch : smoothed(previous: smoothedPitch, current: pitch, factor: pitchSmoothingFactor)

        let stabilizedNote = stabilizeDetectedNote(with: detectNearestNote(for: smoothedPitch), frequency: smoothedPitch)
        detectedNote = stabilizedNote
        publish(.frame(.live(pitch: smoothedPitch, note: stabilizedNote, frameDelta: frameDelta, now: now)))
    }

    private func publish(_ event: TunerSessionEvent) {
        for handler in eventHandlers {
            handler(event)
        }
    }

    private func detectNearestNote(for frequency: Float) -> DetectedNote {
        let midi = calibration.midiNumber(for: Double(frequency))
        return noteFromMIDI(Int(midi.rounded()), frequency: frequency)
    }

    // Prevents one-frame note flips by requiring short consistency before switching labels.
    private func stabilizeDetectedNote(with raw: DetectedNote, frequency: Float) -> DetectedNote {
        if stableMIDI == nil {
            stableMIDI = raw.midiNumber
            candidateMIDI = nil
            candidateStreak = 0
            return raw
        }

        guard let stableMIDI else { return raw }

        if abs(raw.midiNumber - stableMIDI).isMultiple(of: 12),
           abs(raw.centsFromEqualTempered) < 20.0 {
            candidateMIDI = nil
            candidateStreak = 0
            return noteFromMIDI(stableMIDI, frequency: frequency)
        }

        if raw.midiNumber == stableMIDI {
            candidateMIDI = nil
            candidateStreak = 0
            return noteFromMIDI(stableMIDI, frequency: frequency)
        }

        if candidateMIDI == raw.midiNumber {
            candidateStreak += 1
        } else {
            candidateMIDI = raw.midiNumber
            candidateStreak = 1
        }

        if candidateStreak >= noteSwitchRequiredFrames {
            self.stableMIDI = raw.midiNumber
            candidateMIDI = nil
            candidateStreak = 0
            return noteFromMIDI(raw.midiNumber, frequency: frequency)
        }

        return noteFromMIDI(stableMIDI, frequency: frequency)
    }

    private func noteFromMIDI(_ midi: Int, frequency: Float) -> DetectedNote {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = ((midi % 12) + 12) % 12
        let octave = (midi / 12) - 1
        let nearestFrequency = Float(calibration.frequency(ofMIDI: midi))
        let cents = wrappedCents(1200.0 * log2(frequency / nearestFrequency))

        return DetectedNote(
            name: noteNames[noteIndex],
            octave: octave,
            midiNumber: midi,
            nearestFrequency: nearestFrequency,
            centsFromEqualTempered: cents
        )
    }

    private func wrappedCents(_ cents: Float) -> Float {
        cents - (1200.0 * round(cents / 1200.0))
    }

#if DEBUG
    // Debug-only entry point to feed deterministic synthetic frames.
    func debugInjectFrame(pitch: Float, amplitude: Float, timestamp: Date) {
        processAudioData(pitch: pitch, amplitude: amplitude, now: timestamp)
    }
#endif

    // MARK: - Persistence

    private func persistSelection() {
        userDefaults.set(currentInstrument.type.persistenceKey, forKey: PersistenceKey.instrumentType)
        userDefaults.set(Self.tuningSignature(for: currentTuning), forKey: PersistenceKey.tuningSignature)
    }

    private static func restoreInstrument(from userDefaults: UserDefaults) -> Instrument? {
        guard let persistedType = userDefaults.string(forKey: PersistenceKey.instrumentType),
              let instrumentType = InstrumentType(persistenceKey: persistedType) else {
            return nil
        }

        return InstrumentCatalog.selectableInstruments.first { $0.type == instrumentType }
    }

    private static func restoreTuning(for instrument: Instrument, from userDefaults: UserDefaults) -> Tuning? {
        guard let persistedSignature = userDefaults.string(forKey: PersistenceKey.tuningSignature) else {
            return nil
        }

        return instrument.availableTunings.first { tuningSignature(for: $0) == persistedSignature }
    }

    private static func tuningSignature(for tuning: Tuning) -> String {
        let noteSignature = tuning.notes.map(\.fullName).joined(separator: ",")
        return "\(tuning.name)|\(noteSignature)"
    }
}

// Keeps updates stable enough for real-time UI without creating large lag.
func smoothed(previous: Float, current: Float, factor: Float) -> Float {
    (previous * (1.0 - factor)) + (current * factor)
}

private extension InstrumentType {
    var persistenceKey: String {
        switch self {
        case .guitar6:
            return "guitar6"
        case .guitar7:
            return "guitar7"
        case .guitar8:
            return "guitar8"
        case .bass:
            return "bass"
        case .ukulele:
            return "ukulele"
        }
    }

    init?(persistenceKey: String) {
        switch persistenceKey {
        case "guitar6":
            self = .guitar6
        case "guitar7":
            self = .guitar7
        case "guitar8":
            self = .guitar8
        case "bass":
            self = .bass
        case "ukulele":
            self = .ukulele
        default:
            return nil
        }
    }
}
