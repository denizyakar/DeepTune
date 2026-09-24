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

    private let centsSmoothingFactor: Float = 0.2

    init(session: TunerSession) {
        self.session = session
        session.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: TunerSessionEvent) {
        switch event {
        case .frame(.live(_, let note, _, _)):
            handleLiveFrame(note: note)
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
    private func handleLiveFrame(note: DetectedNote) {
        manualCentsDistance = smoothed(
            previous: manualCentsDistance,
            current: max(-50.0, min(50.0, note.centsFromEqualTempered)),
            factor: centsSmoothingFactor
        )

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
