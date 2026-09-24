import Foundation
@testable import DeepTune

/// A conductor that never produces audio, for driving the tuner with injected frames.
final class SilentConductor: TunerConductorType {
    func pitchUpdates() -> AsyncStream<PitchData> { AsyncStream { $0.finish() } }
    func start() {}
    func stop() {}
    func setTrackingTargetFrequency(_ frequency: Float?) {}
    func recentAudioWindow(duration: TimeInterval) -> AudioSampleWindow? { nil }
    func setRecentAudioCaptureEnabled(_ enabled: Bool) {}
}
