import Foundation
import Combine
import AVFoundation
import AudioKit
import SoundpipeAudioKit

// Calculates frequency (pitch) and amplitude of the incoming audio signal
class TunerConductor: ObservableObject {
    @Published var data = PitchData()
    @Published var isStarted = false
    
    let engine = AudioEngine()
    let initialDevice: Device
    
    var mic: AudioEngine.InputNode
    var tappableNodeA: Mixer
    var tappableNodeB: Mixer
    var tappableNodeC: Mixer
    var silencer: Mixer
    
    var tracker: PitchTap!
    
    init() {
        // Essential for iOS/Simulator to allow microphone access
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up AVAudioSession: \(error)")
        }
        
        guard let input = engine.input else {
            fatalError("Audio Engine input node is missing")
        }
        
        // Simulators sometimes fail `engine.inputDevice`. Safe-fallback instead of fatalError.
        if let device = engine.inputDevice {
            initialDevice = device
        } else {
            print("Warning: Could not find input device. This is normal on Simulators.")
            // Use a dummy device or skip assignment if Optional.
            // In AudioKit, if inputDevice is nil, it just uses the default route.
            initialDevice = Device(name: "Simulator Device", deviceID: "SimID")
        }
        
        mic = input
        tappableNodeA = Mixer(mic)
        tappableNodeB = Mixer(tappableNodeA)
        tappableNodeC = Mixer(tappableNodeB)
        silencer = Mixer(tappableNodeC)
        silencer.volume = 0.0
        engine.output = silencer
        
        tracker = PitchTap(mic) { pitch, amp in
            DispatchQueue.main.async {
                self.update(pitch: pitch.first ?? 0.0, amp: amp.first ?? 0.0)
            }
        }
    }
    
    func start() {
        do {
            try engine.start()
            tracker.start()
            isStarted = true
        } catch {
            print("AudioEngine could not start: \(error)")
        }
    }
    
    func stop() {
        engine.stop()
        tracker.stop()
        isStarted = false
    }
    
    private func update(pitch: Float, amp: Float) {
        // Reduced the minimum amplitude to capture softer string vibrations
        guard amp > 0.05 else { return }
        self.data.pitch = pitch
        self.data.amplitude = amp
    }
}

// Data structure to hold the current pitch and amplitude
struct PitchData {
    var pitch: Float = 0.0
    var amplitude: Float = 0.0
}
