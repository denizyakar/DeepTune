import Foundation
import Combine

class TunerViewModel: ObservableObject {
    @Published var currentInstrument: Instrument
    @Published var currentTuning: Tuning
    
    // Values derived from AudioEngine
    @Published var currentPitch: Float = 0.0
    @Published var currentAmplitude: Float = 0.0
    
    // Processed tunings
    @Published var centsDistance: Float = 0.0
    @Published var targetNote: Note?
    @Published var isManualMode: Bool = false
    
    private var conductor = TunerConductor()
    private var cancellables = Set<AnyCancellable>()
    
    init(instrument: Instrument = InstrumentCatalog.guitar6) {
        self.currentInstrument = instrument
        self.currentTuning = instrument.defaultTuning
        
        conductor.$data
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                self?.processAudioData(pitch: data.pitch, amplitude: data.amplitude)
            }
            .store(in: &cancellables)
    }
    
    func start() {
        conductor.start()
    }
    
    func stop() {
        conductor.stop()
    }
    
    func setTargetNote(_ note: Note?) {
        self.targetNote = note
        self.isManualMode = note != nil
    }
    
    // Calculate difference between detected frequency and target frequency
    private func processAudioData(pitch: Float, amplitude: Float) {
        self.currentPitch = pitch
        self.currentAmplitude = amplitude
        
        guard pitch > 0 else { return }
        
        // Use manual target if selected, otherwise find closest in current tuning
        let nearest: Note
        if let target = targetNote, isManualMode {
            nearest = target
        } else {
            nearest = findClosestNote(to: pitch, in: currentTuning.notes)
            self.targetNote = nearest
        }
        
        // Calculates musical cents interval
        // Formulated as: 1200 * log2(freq / target)
        let cents = 1200 * log2(pitch / Float(nearest.frequency))
        
        // Simple smoothing for UI jitter
        let smoothingFactor: Float = 0.2
        let previousCents = self.centsDistance
        self.centsDistance = (self.centsDistance * (1.0 - smoothingFactor)) + (cents * smoothingFactor)
        
        // Haptic Feedback for perfect tuning (within 2 cents)
        if abs(self.centsDistance) < 2.0 && abs(previousCents) >= 2.0 {
            HapticManager.shared.playSuccessHaptic()
        }
    }
    
    // Finds the closest note to the given frequency among tuning notes
    private func findClosestNote(to frequency: Float, in notes: [Note]) -> Note {
        var closestNote = notes[0]
        var minDifference = abs(frequency - Float(notes[0].frequency))
        
        for note in notes {
            let diff = abs(frequency - Float(note.frequency))
            if diff < minDifference {
                closestNote = note
                minDifference = diff
            }
        }
        
        return closestNote
    }
}

