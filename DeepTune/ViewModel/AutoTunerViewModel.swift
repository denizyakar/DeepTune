import Foundation
import Observation

/// Drives the Auto screen: aims at one target string, and moves on once it holds in tune.
@Observable
final class AutoTunerViewModel {
    private enum PersistenceKey {
        static let autoProgressEnabled = "DeepTune.autoProgressEnabled"
    }

    let session: TunerSession

    var isTargetSignalDetected: Bool = false
    var autoCentsDistance: Float = 0.0
    var targetNote: Note?
    var isAutoProgressEnabled: Bool = false {
        didSet {
            persistAutoProgressState()
        }
    }
    var isTuningSuccessful: Bool = false
    var inTuneDuration: Double = 0.0
    private(set) var completedNoteIDs = Set<Note.ID>()

    var hasPitchReference: Bool { session.hasPitchReference }
    var currentInstrument: Instrument { session.currentInstrument }
    var currentTuning: Tuning { session.currentTuning }

    private let userDefaults: UserDefaults

    private let centsSmoothingFactor: Float = 0.2
    private let inTuneEnterWindowCents: Float = 7.0
    private let inTuneExitWindowCents: Float = 11.0
    private let autoAcquireAcceptanceWindowCents: Float = 950.0
    private let successThreshold: Double = 2.5
    private let successLatchDuration: TimeInterval = 1.0

    private var successLatchedUntil: Date?
    private var tuneProgressSeconds: Double = 0.0
    private var recentTargetCentsSamples: [Float] = []
    private var isAutoProgressPending = false

    init(session: TunerSession, userDefaults: UserDefaults = .standard) {
        self.session = session
        self.userDefaults = userDefaults
        self.targetNote = session.currentTuning.notes.first
        self.isAutoProgressEnabled = userDefaults.object(forKey: PersistenceKey.autoProgressEnabled) as? Bool ?? false

        session.subscribe { [weak self] event in
            self?.handle(event)
        }

        applyTrackingTargetToConductor()
        persistAutoProgressState()
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

    var tuneProgressRatio: Double {
        guard successThreshold > 0 else { return 0 }
        return min(1.0, max(0.0, inTuneDuration / successThreshold))
    }

    func isNoteCompleted(_ note: Note) -> Bool {
        completedNoteIDs.contains(note.id)
    }

    // MARK: - Session events

    private func handle(_ event: TunerSessionEvent) {
        switch event {
        case .frame(.silent(let isWithinHoldWindow, let frameDelta, let now)):
            handleSilentFrame(isWithinHoldWindow: isWithinHoldWindow, frameDelta: frameDelta, now: now)
        case .frame(.live(let pitch, _, let frameDelta, let now)):
            handleLiveFrame(pitch: pitch, frameDelta: frameDelta, now: now)
        case .modeChanged:
            isTargetSignalDetected = false
            applyTrackingTargetToConductor()
        case .selectionChanged(let tuning):
            completedNoteIDs.removeAll()
            setTargetNote(tuning.notes.first)
        }
    }

    private func handleSilentFrame(isWithinHoldWindow: Bool, frameDelta: TimeInterval, now: Date) {
        if session.activeMode == .auto {
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
    }

    private func handleLiveFrame(pitch: Float, frameDelta: TimeInterval, now: Date) {
        guard session.activeMode == .auto, let target = targetNote else {
            isTargetSignalDetected = false
            return
        }
        let targetFrequency = Float(target.frequency)
        let targetCents = 1200.0 * log2(pitch / targetFrequency)

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

        // Stabilizes the meter by rejecting fast harmonic spikes and using a median center.
        recentTargetCentsSamples.append(targetCents)
        if recentTargetCentsSamples.count > 5 {
            recentTargetCentsSamples.removeFirst(recentTargetCentsSamples.count - 5)
        }
        let medianTargetCents = median(of: recentTargetCentsSamples) ?? targetCents
        let targetDelta = abs(medianTargetCents - autoCentsDistance)
        let adaptiveFactor: Float = targetDelta > 110 ? 0.08 : centsSmoothingFactor
        let smoothedTargetCents = smoothed(previous: autoCentsDistance, current: medianTargetCents, factor: adaptiveFactor)

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

        handleAutoSuccessIfNeeded(referencePitch: pitch, now: now, frameDelta: frameDelta)
    }

    // MARK: - Auto success

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
        let untuned = session.currentTuning.notes.filter { !completedNoteIDs.contains($0.id) }

        let candidateNotes = untuned.isEmpty ? session.currentTuning.notes : untuned
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

    private func applyTrackingTargetToConductor() {
        guard session.activeMode == .auto, let targetNote else {
            session.setTrackingTargetFrequency(nil)
            return
        }

        session.setTrackingTargetFrequency(Float(targetNote.frequency))
    }

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

    private func persistAutoProgressState() {
        userDefaults.set(isAutoProgressEnabled, forKey: PersistenceKey.autoProgressEnabled)
    }
}
