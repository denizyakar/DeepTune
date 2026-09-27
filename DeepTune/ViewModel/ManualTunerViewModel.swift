import Foundation
import Observation

/// Drives the Manual screen: follows whatever note is played, with no target string.
@Observable
final class ManualTunerViewModel {
    let session: TunerSession

    var manualCentsDistance: Float = 0.0
    var manualLowestFrequency: Float?
    var manualHighestFrequency: Float?

    var detectedNote: DetectedNote? { session.detectedNote }
    var isSignalDetected: Bool { session.isSignalDetected }

    // The same smoothing as Auto, so both meters settle alike.
    private var centsSmoother = CentsSmoother()
    private var smoothedMIDI: Int?

    init(session: TunerSession) {
        self.session = session
        session.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: TunerSessionEvent) {
        switch event {
        case .frame(.live(_, let note, let frameDelta, let now)):
            handleLiveFrame(note: note, frameDelta: frameDelta, now: now)
        case .frame(.silent):
            break
        case .modeChanged(let mode):
            if mode == .manual {
                resetSessionMetrics()
            }
        case .selectionChanged:
            break
        }
    }

    // Runs in every mode, not only on this screen, so the reading is already
    // settled when the user switches here.
    private func handleLiveFrame(note: DetectedNote, frameDelta: TimeInterval, now: Date) {
        let cents = max(-50.0, min(50.0, note.centsFromEqualTempered))
        // Cents are measured from the nearest note, so when that note changes the
        // reading jumps from one edge to the other. Averaging across the jump would
        // sweep the needle through centre and flash a false in-tune; restart instead.
        if note.midiNumber != smoothedMIDI {
            smoothedMIDI = note.midiNumber
            centsSmoother.reset(to: cents)
        }
        manualCentsDistance = centsSmoother.add(cents, at: now, elapsed: frameDelta)

        guard session.activeMode == .manual else { return }

        if let manualLowestFrequency {
            self.manualLowestFrequency = min(manualLowestFrequency, note.nearestFrequency)
        } else {
            manualLowestFrequency = note.nearestFrequency
        }

        if let manualHighestFrequency {
            self.manualHighestFrequency = max(manualHighestFrequency, note.nearestFrequency)
        } else {
            manualHighestFrequency = note.nearestFrequency
        }
    }

    private func resetSessionMetrics() {
        manualLowestFrequency = nil
        manualHighestFrequency = nil
    }
}
