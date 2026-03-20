import Foundation
import Combine

struct DetectedNote: Equatable {
    let name: String
    let octave: Int
    let midiNumber: Int
    let nearestFrequency: Float
    let centsFromEqualTempered: Float
}

enum TunerMode: Hashable {
    case auto
    case manual
}

final class TunerViewModel: ObservableObject {
    private enum PersistenceKey {
        static let instrumentType = "DeepTune.selectedInstrumentType"
        static let tuningSignature = "DeepTune.selectedTuningSignature"
        static let autoProgressEnabled = "DeepTune.autoProgressEnabled"
    }

    @Published var currentInstrument: Instrument
    @Published var currentTuning: Tuning
    
    // Raw values coming from the audio layer.
    @Published var currentPitch: Float = 0.0
    @Published var currentAmplitude: Float = 0.0
    @Published var isSignalDetected: Bool = false
    @Published var isTargetSignalDetected: Bool = false
    @Published var hasPitchReference: Bool = false
    
    // Auto mode output (target-string based).
    @Published var autoCentsDistance: Float = 0.0
    @Published var targetNote: Note?
    @Published var isAutoProgressEnabled: Bool = false {
        didSet {
            persistAutoProgressState()
        }
    }
    @Published var isTuningSuccessful: Bool = false
    @Published var inTuneDuration: Double = 0.0
    @Published private(set) var completedNoteIDs = Set<UUID>()
    
    // Manual mode output (free-pitch based).
    @Published var detectedNote: DetectedNote?
    @Published var manualCentsDistance: Float = 0.0
    @Published var manualLowestFrequency: Float?
    @Published var manualHighestFrequency: Float?
    @Published var activeMode: TunerMode = .auto

    // Backward-compatible binding used by the legacy TunerView branch.
    var centsDistance: Float {
        get { activeMode == .manual ? manualCentsDistance : autoCentsDistance }
        set {
            autoCentsDistance = newValue
            manualCentsDistance = newValue
        }
    }
    
    private let conductorDataPublisher: AnyPublisher<PitchData, Never>
    private let startConductorHandler: () -> Void
    private let stopConductorHandler: () -> Void
    private let setTrackingTargetFrequencyHandler: (Float?) -> Void
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    
    // Keep tuning math centralized and explicit.
    private let referenceA4: Float = 440.0
    private let pitchSmoothingFactor: Float = 0.2
    private let centsSmoothingFactor: Float = 0.2
    private let inTuneEnterWindowCents: Float = 7.0
    private let inTuneExitWindowCents: Float = 11.0
    private let autoAcquireAcceptanceWindowCents: Float = 950.0
    private let successThreshold: Double = 2.5
    private let signalHoldDuration: TimeInterval = 1.0
    private let successLatchDuration: TimeInterval = 1.0
    
    private var smoothedPitch: Float = 0.0
    private var lastProcessFrameAt: Date?
    private var lastLiveSignalAt: Date?
    private var successLatchedUntil: Date?
    private var tuneProgressSeconds: Double = 0.0
    private var recentTargetCentsSamples: [Float] = []
    private var isAutoProgressPending = false
    private var manualStableMIDI: Int?
    private var manualCandidateMIDI: Int?
    private var manualCandidateStreak = 0
    private let manualSwitchRequiredFrames = 4
    
    init(
        instrument: Instrument = InstrumentCatalog.guitar6,
        conductor: TunerConductorType = TunerConductor(),
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        let restoredInstrument = Self.restoreInstrument(from: userDefaults) ?? instrument
        let restoredTuning = Self.restoreTuning(for: restoredInstrument, from: userDefaults) ?? restoredInstrument.defaultTuning

        self.currentInstrument = restoredInstrument
        self.currentTuning = restoredTuning
        self.targetNote = restoredTuning.notes.first
        self.isAutoProgressEnabled = userDefaults.object(forKey: PersistenceKey.autoProgressEnabled) as? Bool ?? false
        self.conductorDataPublisher = conductor.dataPublisher
        self.startConductorHandler = { conductor.start() }
        self.stopConductorHandler = { conductor.stop() }
        self.setTrackingTargetFrequencyHandler = { frequency in
            conductor.setTrackingTargetFrequency(frequency)
        }
        
        conductorDataPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                self?.processAudioData(pitch: data.pitch, amplitude: data.amplitude)
            }
            .store(in: &cancellables)
        
        applyTrackingTargetToConductor()
        persistSelectionState()
        persistAutoProgressState()
    }

    deinit {
        cancellables.removeAll()
    }
    
    func start() {
        startConductorHandler()
    }
    
    func stop() {
        stopConductorHandler()
    }
    
    func setTargetNote(_ note: Note?) {
        let previousTargetID = targetNote?.id
        
        if let incomingNote = note,
           incomingNote.id != previousTargetID,
           completedNoteIDs.contains(incomingNote.id) {
            // Re-entering a completed string intentionally starts a new tuning pass.
            completedNoteIDs.remove(incomingNote.id)
        }
        
        targetNote = note
        isTargetSignalDetected = false
        recentTargetCentsSamples.removeAll()
        applyTrackingTargetToConductor()
        resetAutoSuccessState()
    }
    
    func setInstrumentAndTuning(instrument: Instrument, tuning: Tuning) {
        currentInstrument = instrument
        currentTuning = tuning
        completedNoteIDs.removeAll()
        setTargetNote(tuning.notes.first)
        persistSelectionState()
    }

    func setInstrument(_ instrument: Instrument) {
        if currentInstrument == instrument {
            return
        }
        setInstrumentAndTuning(instrument: instrument, tuning: instrument.defaultTuning)
    }
    
    func setActiveMode(_ mode: TunerMode) {
        activeMode = mode
        isTargetSignalDetected = false
        if mode == .manual {
            resetManualSessionMetrics()
        }
        applyTrackingTargetToConductor()
    }
    
    var isWithinTuneWindow: Bool {
        abs(autoCentsDistance) <= inTuneEnterWindowCents
    }
    
    var tuneProgressRatio: Double {
        guard successThreshold > 0 else { return 0 }
        return min(1.0, max(0.0, inTuneDuration / successThreshold))
    }
    
    func isNoteCompleted(_ note: Note) -> Bool {
        completedNoteIDs.contains(note.id)
    }
    
    // Converts the current frequency to nearest chromatic note using A4=440Hz equal temperament.
    private func detectNearestNote(for frequency: Float) -> DetectedNote {
        let midi = 69.0 + 12.0 * log2(Double(frequency / referenceA4))
        let nearestMIDI = Int(midi.rounded())
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = ((nearestMIDI % 12) + 12) % 12
        let octave = (nearestMIDI / 12) - 1
        
        let nearestFrequency = referenceA4 * pow(2.0, Float(nearestMIDI - 69) / 12.0)
        let cents = wrappedCents(1200.0 * log2(frequency / nearestFrequency))
        
        return DetectedNote(
            name: noteNames[noteIndex],
            octave: octave,
            midiNumber: nearestMIDI,
            nearestFrequency: nearestFrequency,
            centsFromEqualTempered: cents
        )
    }
    
    // Keeps updates stable enough for real-time UI without creating large lag.
    private func smooth(previous: Float, current: Float, factor: Float) -> Float {
        (previous * (1.0 - factor)) + (current * factor)
    }
    
    private func processAudioData(pitch: Float, amplitude: Float) {
        processAudioData(pitch: pitch, amplitude: amplitude, now: Date())
    }
    
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
            if activeMode == .auto {
                isTargetSignalDetected = isWithinHoldWindow && (currentTargetIsCompleted || !recentTargetCentsSamples.isEmpty)
            } else {
                isTargetSignalDetected = false
            }
            
            // Keep the last useful reading for a short period instead of snapping to center.
        if !isWithinHoldWindow {
                if currentTargetIsCompleted {
                    isTuningSuccessful = true
                    tuneProgressSeconds = successThreshold
                    inTuneDuration = tuneProgressSeconds
                } else {
                    tuneProgressSeconds = max(0.0, tuneProgressSeconds - (frameDelta * 0.9))
                    inTuneDuration = tuneProgressSeconds
                    refreshSuccessLatch(now: now)
                }
            }
            
            return
        }
        
        isSignalDetected = true
        hasPitchReference = true
        lastLiveSignalAt = now
        smoothedPitch = smoothedPitch == 0 ? pitch : smooth(previous: smoothedPitch, current: pitch, factor: pitchSmoothingFactor)
        
        let nearestNote = detectNearestNote(for: smoothedPitch)
        let stabilizedNote = stabilizeManualDetectedNote(with: nearestNote, frequency: smoothedPitch)
        detectedNote = stabilizedNote
        manualCentsDistance = smooth(
            previous: manualCentsDistance,
            current: max(-50.0, min(50.0, stabilizedNote.centsFromEqualTempered)),
            factor: centsSmoothingFactor
        )
        if activeMode == .manual {
            if let manualLowestFrequency {
                self.manualLowestFrequency = min(manualLowestFrequency, stabilizedNote.nearestFrequency)
            } else {
                manualLowestFrequency = stabilizedNote.nearestFrequency
            }
            
            if let manualHighestFrequency {
                self.manualHighestFrequency = max(manualHighestFrequency, stabilizedNote.nearestFrequency)
            } else {
                manualHighestFrequency = stabilizedNote.nearestFrequency
            }
        }
        
        guard activeMode == .auto, let target = targetNote else {
            isTargetSignalDetected = false
            return
        }
        let targetFrequency = Float(target.frequency)
        let targetCents = 1200.0 * log2(smoothedPitch / targetFrequency)
        
        guard abs(targetCents) <= autoAcquireAcceptanceWindowCents else {
            isTargetSignalDetected = false
            if !currentTargetIsCompleted {
                tuneProgressSeconds = max(0.0, tuneProgressSeconds - (frameDelta * 1.1))
                inTuneDuration = tuneProgressSeconds
                refreshSuccessLatch(now: now)
            }
            return
        }
        
        isTargetSignalDetected = true
        let normalizedPitch = smoothedPitch
        
        // Stabilizes the meter by rejecting fast harmonic spikes and using a median center.
        recentTargetCentsSamples.append(targetCents)
        if recentTargetCentsSamples.count > 5 {
            recentTargetCentsSamples.removeFirst(recentTargetCentsSamples.count - 5)
        }
        let medianTargetCents = median(of: recentTargetCentsSamples) ?? targetCents
        let targetDelta = abs(medianTargetCents - autoCentsDistance)
        let adaptiveFactor: Float = targetDelta > 110 ? 0.08 : centsSmoothingFactor
        let smoothedTargetCents = smooth(previous: autoCentsDistance, current: medianTargetCents, factor: adaptiveFactor)
        
        // Limits unrealistically fast meter jumps caused by harmonics/noise spikes.
        let dynamicRateLimit: Float
        if abs(autoCentsDistance) > 300 {
            dynamicRateLimit = 320
        } else if abs(autoCentsDistance) > 90 {
            dynamicRateLimit = 180
        } else {
            dynamicRateLimit = 120
        }
        let maxStep = Float(frameDelta) * dynamicRateLimit
        let delta = smoothedTargetCents - autoCentsDistance
        let limitedDelta = max(-maxStep, min(maxStep, delta))
        autoCentsDistance += limitedDelta
        
        handleAutoSuccessIfNeeded(referencePitch: normalizedPitch, now: now, frameDelta: frameDelta)
    }
    
    private func handleAutoSuccessIfNeeded(referencePitch: Float, now: Date, frameDelta: TimeInterval) {
        if currentTargetIsCompleted {
            isTuningSuccessful = true
            tuneProgressSeconds = successThreshold
            inTuneDuration = tuneProgressSeconds
            return
        }
        
        let absoluteCents = abs(autoCentsDistance)
        let stableWindow = isTuningSuccessful ? inTuneExitWindowCents : inTuneEnterWindowCents
        
        if absoluteCents <= inTuneEnterWindowCents {
            tuneProgressSeconds = min(successThreshold, tuneProgressSeconds + frameDelta)
        } else if absoluteCents <= stableWindow {
            tuneProgressSeconds = max(0.0, tuneProgressSeconds - (frameDelta * 0.25))
        } else {
            tuneProgressSeconds = max(0.0, tuneProgressSeconds - (frameDelta * 1.5))
        }
        
        inTuneDuration = tuneProgressSeconds
        
        if tuneProgressSeconds < successThreshold {
            refreshSuccessLatch(now: now)
            return
        }
        
        if !isTuningSuccessful {
            isTuningSuccessful = true
            successLatchedUntil = now.addingTimeInterval(successLatchDuration)
            if let targetNote {
                completedNoteIDs.insert(targetNote.id)
            }
            HapticManager.shared.playSuccessHaptic()
        }
        
        guard isAutoProgressEnabled, !isAutoProgressPending else { return }
        progressToNextString(referencePitch: referencePitch)
    }
    
    private func progressToNextString(referencePitch: Float) {
        guard let currentTarget = targetNote else { return }
        
        completedNoteIDs.insert(currentTarget.id)
        let untuned = currentTuning.notes.filter { !completedNoteIDs.contains($0.id) }
        
        let candidateNotes = untuned.isEmpty ? currentTuning.notes : untuned
        if untuned.isEmpty {
            completedNoteIDs.removeAll()
        }
        
        // Picks the next target by nearest frequency to the currently played pitch.
        let nextNote = candidateNotes.min { lhs, rhs in
            abs(Float(lhs.frequency) - referencePitch) < abs(Float(rhs.frequency) - referencePitch)
        }
        
        guard let resolvedNextNote = nextNote else { return }
        isAutoProgressPending = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.setTargetNote(resolvedNextNote)
            self.isAutoProgressPending = false
        }
    }
    
    private func resetAutoSuccessState() {
        tuneProgressSeconds = 0.0
        inTuneDuration = tuneProgressSeconds
        isTuningSuccessful = false
        successLatchedUntil = nil
        recentTargetCentsSamples.removeAll()
    }

    private func resetManualSessionMetrics() {
        manualLowestFrequency = nil
        manualHighestFrequency = nil
    }
    
    private func refreshSuccessLatch(now: Date) {
        guard let successLatchedUntil else {
            isTuningSuccessful = false
            return
        }
        
        isTuningSuccessful = now <= successLatchedUntil
        if now > successLatchedUntil {
            self.successLatchedUntil = nil
        }
    }
    
    private var currentTargetIsCompleted: Bool {
        guard let targetNote else { return false }
        return completedNoteIDs.contains(targetNote.id)
    }
    
    // Prevents one-frame note flips in manual mode by requiring short consistency before switching labels.
    private func stabilizeManualDetectedNote(with raw: DetectedNote, frequency: Float) -> DetectedNote {
        if manualStableMIDI == nil {
            manualStableMIDI = raw.midiNumber
            manualCandidateMIDI = nil
            manualCandidateStreak = 0
            return raw
        }
        
        guard let stableMIDI = manualStableMIDI else { return raw }
        
        if abs(raw.midiNumber - stableMIDI).isMultiple(of: 12),
           abs(raw.centsFromEqualTempered) < 20.0 {
            manualCandidateMIDI = nil
            manualCandidateStreak = 0
            return noteFromMIDI(stableMIDI, frequency: frequency)
        }
        
        if raw.midiNumber == stableMIDI {
            manualCandidateMIDI = nil
            manualCandidateStreak = 0
            return noteFromMIDI(stableMIDI, frequency: frequency)
        }
        
        if manualCandidateMIDI == raw.midiNumber {
            manualCandidateStreak += 1
        } else {
            manualCandidateMIDI = raw.midiNumber
            manualCandidateStreak = 1
        }
        
        if manualCandidateStreak >= manualSwitchRequiredFrames {
            manualStableMIDI = raw.midiNumber
            manualCandidateMIDI = nil
            manualCandidateStreak = 0
            return noteFromMIDI(raw.midiNumber, frequency: frequency)
        }
        
        return noteFromMIDI(stableMIDI, frequency: frequency)
    }
    
    private func noteFromMIDI(_ midi: Int, frequency: Float) -> DetectedNote {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = ((midi % 12) + 12) % 12
        let octave = (midi / 12) - 1
        let nearestFrequency = referenceA4 * pow(2.0, Float(midi - 69) / 12.0)
        let cents = wrappedCents(1200.0 * log2(frequency / nearestFrequency))
        
        return DetectedNote(
            name: noteNames[noteIndex],
            octave: octave,
            midiNumber: midi,
            nearestFrequency: nearestFrequency,
            centsFromEqualTempered: cents
        )
    }
    
    private func applyTrackingTargetToConductor() {
        guard activeMode == .auto, let targetNote else {
            setTrackingTargetFrequencyHandler(nil)
            return
        }
        
        setTrackingTargetFrequencyHandler(Float(targetNote.frequency))
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
    
    private func median(of values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            return sorted[middle]
        }
    }

    private func persistSelectionState() {
        userDefaults.set(currentInstrument.type.persistenceKey, forKey: PersistenceKey.instrumentType)
        userDefaults.set(Self.tuningSignature(for: currentTuning), forKey: PersistenceKey.tuningSignature)
    }

    private func persistAutoProgressState() {
        userDefaults.set(isAutoProgressEnabled, forKey: PersistenceKey.autoProgressEnabled)
    }

    private static func restoreInstrument(from userDefaults: UserDefaults) -> Instrument? {
        guard let persistedType = userDefaults.string(forKey: PersistenceKey.instrumentType),
              let instrumentType = InstrumentType(persistenceKey: persistedType) else {
            return nil
        }

        return InstrumentCatalog.allInstruments.first { $0.type == instrumentType }
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
