import Foundation
import AVFoundation
import OSLog
import AudioKit
import SoundpipeAudioKit

protocol TunerConductorType: AnyObject {
    func pitchUpdates() -> AsyncStream<PitchData>
    func start()
    func stop()
    func setTrackingTargetFrequency(_ frequency: Float?)
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow?
    func setRecentAudioCaptureEnabled(_ enabled: Bool)
}

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeepTune", category: "audio")

// Calculates frequency (pitch) and amplitude of the incoming audio signal
class TunerConductor: TunerConductorType {
    // Every assignment is published, so each frame must assign the whole value
    // once; setting pitch and amplitude separately would emit a half-updated frame.
    private var data = PitchData() {
        didSet { pitchContinuation?.yield(data) }
    }
    private var pitchContinuation: AsyncStream<PitchData>.Continuation?
    private(set) var isStarted = false
    
    let engine = AudioEngine()
    let initialDevice: Device
    
    var mic: Node
    var tappableNodeA: Mixer
    var tappableNodeB: Mixer
    var tappableNodeC: Mixer
    var silencer: Mixer
    
    var tracker: PitchTap!

    private var frameFilter = PitchFrameFilter()
    private let recentAudioQueue = DispatchQueue(label: "DeepTune.TunerConductor.RecentAudio")
    private var recentAudioBuffer: AudioRingBuffer?
    private var recentAudioSampleRate: Double = 44_100.0
    private let maxRecentAudioDuration: TimeInterval = 8.0
    private var isCaptureTapInstalled = false
    // Only the chord finder needs the raw sample window, so the capture tap stays
    // off while tuning: it would otherwise copy every buffer for nobody.
    private var isRecentAudioCaptureEnabled = false
    // Whether the app wants audio running, as opposed to whether it currently is:
    // an interruption stops the engine without changing the intent.
    private var isRunningIntended = false
    private var sessionObservers: [NSObjectProtocol] = []

    /// A fresh stream per call. Starting a new one finishes the previous one, so a
    /// restarted `task()` never leaves an earlier consumer waiting forever.
    func pitchUpdates() -> AsyncStream<PitchData> {
        pitchContinuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: PitchData.self)
        pitchContinuation = continuation
        return stream
    }
    
    init() {
        // The category has to be in place before `engine.input` is touched below,
        // but activation is deliberately deferred to `start()`: activating here
        // would claim the audio session at launch, before the user tunes anything.
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
        } catch {
            logger.error("Failed to configure AVAudioSession category: \(error, privacy: .public)")
        }

        // Simulators sometimes fail `engine.inputDevice`. Safe-fallback instead of fatalError.
        if let device = engine.inputDevice {
            initialDevice = device
        } else {
            logger.notice("No input device found; expected on Simulator")
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
        
        // PitchTap retains this closure, and the tracker is stored on self, so a
        // strong capture here would keep the conductor (and its audio engine)
        // alive forever and stop deinit from ever removing the taps.
        // AudioKit already delivers this on the main queue, so no hop is needed.
        tracker = PitchTap(mic) { [weak self] pitch, amp in
            self?.update(pitch: pitch.first ?? 0.0, amp: amp.first ?? 0.0)
        }

        observeAudioSessionDisruptions()
    }

    func start() {
        isRunningIntended = true
        startEngine()
    }

    func stop() {
        isRunningIntended = false
        stopEngine()

        // Politeness: `.mixWithOthers` means other audio may be playing, and
        // deactivation can legitimately fail while it is.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startEngine() {
        guard !isStarted else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            tracker.start()
            if isRecentAudioCaptureEnabled {
                installRecentAudioTapIfNeeded()
            }
            isStarted = true
        } catch {
            logger.error("AudioEngine could not start: \(error, privacy: .public)")
            isStarted = false
        }
    }

    private func stopEngine() {
        removeRecentAudioTapIfNeeded()
        engine.stop()
        tracker.stop()
        isStarted = false
    }

    /// A phone call or an unplugged pair of headphones stops the engine underneath
    /// us. Without this the tuner goes silently dead until the user leaves and
    /// re-enters the screen.
    private func observeAudioSessionDisruptions() {
        let center = NotificationCenter.default

        let interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        let routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.handleRouteChange()
        }

        sessionObservers = [interruptionObserver, routeChangeObserver]
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            // The system has already stopped the engine; just record that.
            stopEngine()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume), isRunningIntended {
                startEngine()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange() {
        guard isRunningIntended else { return }

        // Restart on any route change: the engine's input node is bound to the
        // previous route and stays silent otherwise.
        stopEngine()
        startEngine()
    }

    func setRecentAudioCaptureEnabled(_ enabled: Bool) {
        guard isRecentAudioCaptureEnabled != enabled else { return }
        isRecentAudioCaptureEnabled = enabled

        if enabled {
            if isStarted {
                installRecentAudioTapIfNeeded()
            }
        } else {
            removeRecentAudioTapIfNeeded()
            recentAudioQueue.async { [weak self] in
                self?.recentAudioBuffer?.removeAll()
            }
        }
    }
    
    func setTrackingTargetFrequency(_ frequency: Float?) {
        frameFilter.setTrackingTargetFrequency(frequency)
    }

    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? {
        recentAudioQueue.sync {
            guard let recentAudioBuffer, !recentAudioBuffer.isEmpty, recentAudioSampleRate > 0 else {
                return nil
            }
            let requestedFrameCount = max(1, Int(duration * recentAudioSampleRate))
            let window = recentAudioBuffer.lastSamples(requestedFrameCount)
            guard !window.isEmpty else { return nil }

            return AudioSampleWindow(samples: window, sampleRate: recentAudioSampleRate)
        }
    }

    deinit {
        pitchContinuation?.finish()
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        removeRecentAudioTapIfNeeded()
    }
    
    private func update(pitch: Float, amp: Float) {
        data = frameFilter.process(pitch: pitch, amp: amp, now: Date())
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

        let sampleRate = buffer.format.sampleRate
        recentAudioQueue.async { [weak self] in
            guard let self else { return }

            let capacity = max(1, Int(self.maxRecentAudioDuration * sampleRate))
            if self.recentAudioBuffer == nil || self.recentAudioSampleRate != sampleRate {
                self.recentAudioSampleRate = sampleRate
                self.recentAudioBuffer = AudioRingBuffer(capacity: capacity)
            }

            self.recentAudioBuffer?.append(samples)
        }
    }
}

