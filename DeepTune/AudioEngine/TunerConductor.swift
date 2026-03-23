import Foundation
import Combine
import AVFoundation
import AudioKit
import SoundpipeAudioKit

protocol TunerConductorType: AnyObject {
    var dataPublisher: AnyPublisher<PitchData, Never> { get }
    func start()
    func stop()
    func setTrackingTargetFrequency(_ frequency: Float?)
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow?
}

// Calculates frequency (pitch) and amplitude of the incoming audio signal
class TunerConductor: ObservableObject, TunerConductorType {
    @Published var data = PitchData()
    @Published var isStarted = false
    
    let engine = AudioEngine()
    let initialDevice: Device
    
    var mic: Node
    var tappableNodeA: Mixer
    var tappableNodeB: Mixer
    var tappableNodeC: Mixer
    var silencer: Mixer
    
    var tracker: PitchTap!

    private enum AutoTrackingState {
        case acquire
        case fineLock
    }
    
    private let autoSignalOnThreshold: Float = 0.014
    private let autoSignalOffThreshold: Float = 0.008
    private let manualSignalOnThreshold: Float = 0.009
    private let manualSignalOffThreshold: Float = 0.0045
    private let manualMinTrackablePitch: Float = 30.0
    private let manualMaxTrackablePitch: Float = 1800.0
    private let autoMinTrackablePitch: Float = 30.0
    private let autoMaxTrackablePitch: Float = 1800.0
    private let autoTransientIgnoreDuration: TimeInterval = 0.06
    private let manualTransientIgnoreDuration: TimeInterval = 0.02
    private let autoAcquireWindowCents: Float = 950.0
    private let autoFineLockWindowCents: Float = 280.0
    private let fineLockEnterCents: Float = 240.0
    private let fineLockExitCents: Float = 360.0
    private let octaveShiftPenaltyAcquire: Float = 260.0
    private let octaveShiftPenaltyFineLock: Float = 380.0
    private let harmonicPenaltyAcquire: Float = 34.0
    private let harmonicPenaltyFineLock: Float = 55.0
    private let acquireStableFramesToLock = 3
    private let fineLockMissFramesToDrop = 4
    private let rejectionHoldDuration: TimeInterval = 0.12
    private let amplitudeSmoothingFactor: Float = 0.25
    private var smoothedAmplitude: Float = 0.0
    private var isSignalOpen = false
    private var signalOpenedAt: Date?
    private var lastAcceptedPitch: Float = 0.0
    private var lastAcceptedAt: Date?
    private var trackingTargetFrequency: Float?
    private var autoTrackingState: AutoTrackingState = .acquire
    private var acquireStableFrameCount = 0
    private var fineLockMissFrameCount = 0
    private let recentAudioQueue = DispatchQueue(label: "DeepTune.TunerConductor.RecentAudio")
    private var recentAudioSamples: [Float] = []
    private var recentAudioSampleRate: Double = 44_100.0
    private let maxRecentAudioDuration: TimeInterval = 8.0
    private var isCaptureTapInstalled = false

    var dataPublisher: AnyPublisher<PitchData, Never> {
        $data.eraseToAnyPublisher()
    }
    
    init() {
        // Essential for iOS/Simulator to allow microphone access
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up AVAudioSession: \(error)")
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
        if let input = engine.input {
            mic = input
        } else {
            // Keep unit tests and no-input environments alive with a silent fallback node.
            mic = Mixer()
        }
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

        installRecentAudioTapIfNeeded()
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
        resetAutoTrackingState()
    }

    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? {
        recentAudioQueue.sync {
            guard !recentAudioSamples.isEmpty, recentAudioSampleRate > 0 else { return nil }
            let requestedFrameCount = max(1, Int(duration * recentAudioSampleRate))
            let frameCount = min(requestedFrameCount, recentAudioSamples.count)
            guard frameCount > 0 else { return nil }

            let window = Array(recentAudioSamples.suffix(frameCount))
            return AudioSampleWindow(samples: window, sampleRate: recentAudioSampleRate)
        }
    }

    deinit {
        removeRecentAudioTapIfNeeded()
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
        
        let pitchBounds = resolvedTrackablePitchBounds(isTargetedTracking: isTargetedTracking)
        guard isSignalOpen,
              pitch >= pitchBounds.lowerBound,
              pitch <= pitchBounds.upperBound else {
            registerAutoTrackingMissIfNeeded()
            self.data = PitchData()
            return
        }
        
        // Ignore the first short transient right after signal opens.
        if let signalOpenedAt, now.timeIntervalSince(signalOpenedAt) < transientIgnoreDuration {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }

        guard let resolved = resolvePitchCandidate(rawPitch: pitch) else {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }

        if isUnstableHarmonicJump(newPitch: resolved.pitch, now: now) {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                self.data = PitchData()
            } else {
                publishRejectedFrameFallback(now: now)
            }
            return
        }

        if let centsFromTarget = resolved.centsFromTarget {
            updateAutoTrackingState(absTargetCents: abs(centsFromTarget))
        } else {
            resetAutoTrackingState()
        }

        lastAcceptedPitch = resolved.pitch
        lastAcceptedAt = now

        self.data.pitch = resolved.pitch
        self.data.amplitude = smoothedAmplitude
    }

    private struct ResolvedPitchCandidate {
        let pitch: Float
        let centsFromTarget: Float?
    }

    private func resolvePitchCandidate(rawPitch: Float) -> ResolvedPitchCandidate? {
        guard let targetFrequency = trackingTargetFrequency else {
            return ResolvedPitchCandidate(pitch: rawPitch, centsFromTarget: nil)
        }

        var bestPitch: Float?
        var bestCents: Float = 0.0
        var bestScore: Float = .greatestFiniteMagnitude
        // Keep octave harmonics (x2) but avoid 3rd-harmonic remapping that can create false locks.
        let divisors: [Float] = [1, 2]
        let octavePenalty = autoTrackingState == .fineLock ? octaveShiftPenaltyFineLock : octaveShiftPenaltyAcquire
        let harmonicPenalty = autoTrackingState == .fineLock ? harmonicPenaltyFineLock : harmonicPenaltyAcquire
        let activeWindowCents = autoTrackingState == .fineLock ? autoFineLockWindowCents : autoAcquireWindowCents

        for divisor in divisors {
            let base = rawPitch / divisor
            for octaveShift in -2...2 {
                let candidate = base * pow(2.0, Float(octaveShift))
                guard candidate >= autoMinTrackablePitch, candidate <= autoMaxTrackablePitch else { continue }

                let cents = 1200.0 * log2(candidate / targetFrequency)
                let absCents = abs(cents)
                guard absCents <= activeWindowCents else { continue }

                var score = absCents
                score += abs(Float(octaveShift)) * octavePenalty
                if divisor != 1 {
                    score += harmonicPenalty
                }

                if score < bestScore {
                    bestScore = score
                    bestPitch = candidate
                    bestCents = cents
                }
            }
        }

        guard let resolved = bestPitch else {
            return nil
        }

        return ResolvedPitchCandidate(pitch: resolved, centsFromTarget: bestCents)
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

    private func resolvedTrackablePitchBounds(isTargetedTracking: Bool) -> ClosedRange<Float> {
        if isTargetedTracking {
            return autoMinTrackablePitch...autoMaxTrackablePitch
        }
        return manualMinTrackablePitch...manualMaxTrackablePitch
    }

    private func updateAutoTrackingState(absTargetCents: Float) {
        guard trackingTargetFrequency != nil else {
            resetAutoTrackingState()
            return
        }

        switch autoTrackingState {
        case .acquire:
            fineLockMissFrameCount = 0
            if absTargetCents <= fineLockEnterCents {
                acquireStableFrameCount += 1
                if acquireStableFrameCount >= acquireStableFramesToLock {
                    autoTrackingState = .fineLock
                    acquireStableFrameCount = 0
                }
            } else {
                acquireStableFrameCount = 0
            }
        case .fineLock:
            if absTargetCents > fineLockExitCents {
                fineLockMissFrameCount += 1
                if fineLockMissFrameCount >= fineLockMissFramesToDrop {
                    resetAutoTrackingState()
                }
            } else {
                fineLockMissFrameCount = 0
            }
        }
    }

    private func registerAutoTrackingMissIfNeeded() {
        guard trackingTargetFrequency != nil else { return }

        switch autoTrackingState {
        case .acquire:
            acquireStableFrameCount = 0
        case .fineLock:
            fineLockMissFrameCount += 1
            if fineLockMissFrameCount >= fineLockMissFramesToDrop {
                resetAutoTrackingState()
            }
        }
    }

    private func resetAutoTrackingState() {
        autoTrackingState = .acquire
        acquireStableFrameCount = 0
        fineLockMissFrameCount = 0
    }
    
    private func resolvedSignalOnThreshold(isTargetedTracking: Bool) -> Float {
        guard isTargetedTracking else { return manualSignalOnThreshold }
        guard let target = trackingTargetFrequency else { return autoSignalOnThreshold }
        
        // Very low strings and very high strings tend to present less stable amplitudes on phone mics.
        if target < 70 || target > 420 {
            return autoSignalOnThreshold * 0.64
        }

        if target < 95 || target > 300 {
            return autoSignalOnThreshold * 0.72
        }
        
        return autoSignalOnThreshold
    }
    
    private func resolvedSignalOffThreshold(isTargetedTracking: Bool) -> Float {
        guard isTargetedTracking else { return manualSignalOffThreshold }
        guard let target = trackingTargetFrequency else { return autoSignalOffThreshold }
        
        if target < 70 || target > 420 {
            return autoSignalOffThreshold * 0.64
        }

        if target < 95 || target > 300 {
            return autoSignalOffThreshold * 0.72
        }
        
        return autoSignalOffThreshold
    }

    private func installRecentAudioTapIfNeeded() {
        let captureNode = tappableNodeC.avAudioNode
        let bus: AVAudioNodeBus = 0
        let format = captureNode.outputFormat(forBus: bus)

        guard format.sampleRate > 0 else { return }
        captureNode.installTap(onBus: bus, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.appendRecentAudio(buffer)
        }
        isCaptureTapInstalled = true
    }

    private func removeRecentAudioTapIfNeeded() {
        guard isCaptureTapInstalled else { return }
        tappableNodeC.avAudioNode.removeTap(onBus: 0)
        isCaptureTapInstalled = false
    }

    private func appendRecentAudio(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples: [Float]
        if let floatChannelData = buffer.floatChannelData {
            samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
        } else if let int16ChannelData = buffer.int16ChannelData {
            let source = UnsafeBufferPointer(start: int16ChannelData[0], count: frameLength)
            samples = source.map { Float($0) / 32768.0 }
        } else {
            return
        }

        recentAudioQueue.async { [weak self] in
            guard let self else { return }

            self.recentAudioSampleRate = buffer.format.sampleRate
            self.recentAudioSamples.append(contentsOf: samples)

            let maxFrameCount = Int(self.maxRecentAudioDuration * self.recentAudioSampleRate)
            if self.recentAudioSamples.count > maxFrameCount {
                self.recentAudioSamples.removeFirst(self.recentAudioSamples.count - maxFrameCount)
            }
        }
    }
}

// Data structure to hold the current pitch and amplitude
struct PitchData {
    var pitch: Float = 0.0
    var amplitude: Float = 0.0
}
