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
            
            // Low E String chosen at the start
            self.targetNote = instrument.defaultTuning.notes.first
            self.isManualMode = true
            
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
            
            // Ses yoksa veya hedef nota seçili değilse işlem yapma
            guard pitch > 0, let target = targetNote else { return }
            
            // Sadece seçili olan hedef notanın frekansına göre cent farkını hesapla
            let targetFrequency = Float(target.frequency)
            let cents = 1200 * log2(pitch / targetFrequency)
            
            // UI titremesini önlemek için yumuşatma (Smoothing)
            let smoothingFactor: Float = 0.2
            self.centsDistance = (self.centsDistance * (1.0 - smoothingFactor)) + (cents * smoothingFactor)
            
            handleSuccessTracking()
        }
    
    @Published var isAutoProgressEnabled: Bool = false
    @Published var inTuneDuration: Double = 0.0 // Duration student is perfectly in tune
    @Published var isTuningSuccessful: Bool = false // Becomes true when inTuneDuration > threshold
    
    private var inTuneStartTime: Date?
    private let successThreshold: Double = 2.0 // Seconds
    
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
    
    private func handleSuccessTracking() {
        if abs(self.centsDistance) < 5.0 {
            if inTuneStartTime == nil {
                inTuneStartTime = Date()
            } else if let startTime = inTuneStartTime {
                inTuneDuration = Date().timeIntervalSince(startTime)
                if inTuneDuration >= successThreshold && !isTuningSuccessful {
                    isTuningSuccessful = true
                    HapticManager.shared.playSuccessHaptic()
                    
                    if isAutoProgressEnabled {
                        progressToNextString()
                    }
                }
            }
        } else {
            // Reset if out of tune
            inTuneStartTime = nil
            inTuneDuration = 0.0
            isTuningSuccessful = false
        }
    }
    
    private func progressToNextString() {
        guard let currentTarget = targetNote,
              let currentIndex = currentTuning.notes.firstIndex(of: currentTarget) else { return }
        
        // Find next string (loop back or stop, we will loop for now)
        let nextIndex = (currentIndex + 1) % currentTuning.notes.count
        
        // Small delay to let user see success before jumping
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.setTargetNote(self.currentTuning.notes[nextIndex])
            // Force manual mode on to keep the specific target active
            self.isManualMode = true
        }
    }
}


