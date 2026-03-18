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
    
    private let autoSignalOnThreshold: Float = 0.014
    private let autoSignalOffThreshold: Float = 0.008
    private let manualSignalOnThreshold: Float = 0.009
    private let manualSignalOffThreshold: Float = 0.0045
    private let minTrackablePitch: Float = 60.0
    private let maxTrackablePitch: Float = 1400.0
    private let autoTransientIgnoreDuration: TimeInterval = 0.06
    private let manualTransientIgnoreDuration: TimeInterval = 0.02
    private let maxTargetOffsetCents: Float = 280.0
    private let rejectionHoldDuration: TimeInterval = 0.12
    private let amplitudeSmoothingFactor: Float = 0.25
    private var smoothedAmplitude: Float = 0.0
    private var isSignalOpen = false
    private var signalOpenedAt: Date?
    private var lastAcceptedPitch: Float = 0.0
    private var lastAcceptedAt: Date?
    private var trackingTargetFrequency: Float?
    
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
    
    func setTrackingTargetFrequency(_ frequency: Float?) {
        trackingTargetFrequency = frequency
        lastAcceptedPitch = 0.0
        lastAcceptedAt = nil
    }
    
    private func update(pitch: Float, amp: Float) {
        let now = Date()
        let isTargetedTracking = trackingTargetFrequency != nil
        let signalOnThreshold = resolvedSignalOnThreshold(isTargetedTracking: isTargetedTracking)
        let signalOffThreshold = resolvedSignalOffThreshold(isTargetedTracking: isTargetedTracking)
        let transientIgnoreDuration = isTargetedTracking ? autoTransientIgnoreDuration : manualTransientIgnoreDuration

        smoothedAmplitude = (smoothedAmplitude * (1.0 - amplitudeSmoothingFactor)) + (amp * amplitudeSmoothingFactor)
        
        // Use gate hysteresis to prevent flickering between "signal" and "no signal".
        let wasSignalOpen = isSignalOpen
        if isSignalOpen {
            if smoothedAmplitude < signalOffThreshold {
                isSignalOpen = false
            }
        } else if smoothedAmplitude > signalOnThreshold {
            isSignalOpen = true
        }
        
        if !wasSignalOpen && isSignalOpen {
            signalOpenedAt = now
        }
        
        if wasSignalOpen && !isSignalOpen {
            signalOpenedAt = nil
        }
        
        guard isSignalOpen,
              pitch >= minTrackablePitch,
              pitch <= maxTrackablePitch else {
            self.data = PitchData()
            return
        }
        
        // Ignore the first short transient right after signal opens.
        if let signalOpenedAt, now.timeIntervalSince(signalOpenedAt) < transientIgnoreDuration {
            if isTargetedTracking {
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }
        
        guard let resolvedPitch = resolvePitchCandidate(rawPitch: pitch) else {
            if isTargetedTracking {
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }
        
        if isUnstableHarmonicJump(newPitch: resolvedPitch, now: now) {
            if isTargetedTracking {
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }
        
        lastAcceptedPitch = resolvedPitch
        lastAcceptedAt = now
        
        self.data.pitch = resolvedPitch
        self.data.amplitude = smoothedAmplitude
    }
    
    private func resolvePitchCandidate(rawPitch: Float) -> Float? {
        guard let targetFrequency = trackingTargetFrequency else {
            return rawPitch
        }
        
        var bestPitch: Float?
        var bestAbsCents: Float = .greatestFiniteMagnitude
        // Keep octave harmonics (x2) but avoid 3rd-harmonic remapping that can create false locks.
        let divisors: [Float] = [1, 2]
        
        for divisor in divisors {
            let base = rawPitch / divisor
            for octaveShift in -2...2 {
                let candidate = base * pow(2.0, Float(octaveShift))
                guard candidate >= minTrackablePitch, candidate <= maxTrackablePitch else { continue }
                
                let cents = 1200.0 * log2(candidate / targetFrequency)
                let absCents = abs(cents)
                if absCents < bestAbsCents {
                    bestAbsCents = absCents
                    bestPitch = candidate
                }
            }
        }
        
        guard let resolved = bestPitch, bestAbsCents <= maxTargetOffsetCents else {
            return nil
        }
        
        return resolved
    }
    
    private func isUnstableHarmonicJump(newPitch: Float, now: Date) -> Bool {
        guard trackingTargetFrequency != nil else { return false }
        guard lastAcceptedPitch > 0, let lastAcceptedAt else { return false }
        let deltaTime = now.timeIntervalSince(lastAcceptedAt)
        guard deltaTime < 0.08 else { return false }
        
        let ratio = max(newPitch, lastAcceptedPitch) / min(newPitch, lastAcceptedPitch)
        return ratio > 1.75 && ratio < 2.25
    }
    
    private func publishRejectedFrameFallback(now: Date) {
        guard lastAcceptedPitch > 0,
              let lastAcceptedAt,
              now.timeIntervalSince(lastAcceptedAt) <= rejectionHoldDuration else {
            self.data = PitchData()
            return
        }
        
        self.data.pitch = lastAcceptedPitch
        self.data.amplitude = max(smoothedAmplitude * 0.65, 0.005)
    }
    
    private func resolvedSignalOnThreshold(isTargetedTracking: Bool) -> Float {
        guard isTargetedTracking else { return manualSignalOnThreshold }
        guard let target = trackingTargetFrequency else { return autoSignalOnThreshold }
        
        // Low E / High E strings tend to present less stable amplitudes on phone mics.
        if target < 95 || target > 300 {
            return autoSignalOnThreshold * 0.72
        }
        
        return autoSignalOnThreshold
    }
    
    private func resolvedSignalOffThreshold(isTargetedTracking: Bool) -> Float {
        guard isTargetedTracking else { return manualSignalOffThreshold }
        guard let target = trackingTargetFrequency else { return autoSignalOffThreshold }
        
        if target < 95 || target > 300 {
            return autoSignalOffThreshold * 0.72
        }
        
        return autoSignalOffThreshold
    }
}

// Data structure to hold the current pitch and amplitude
struct PitchData {
    var pitch: Float = 0.0
    var amplitude: Float = 0.0
}
