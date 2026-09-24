import Foundation

/// What the chord finder needs from a chord analyzer. Abstracted so tests can
/// hold an analysis open and decide exactly when it returns.
///
/// `nonisolated` because the app target defaults to MainActor isolation: without it
/// this protocol would be main-actor-bound and no actor could implement it.
nonisolated protocol ChordAnalyzing: Sendable {
    func prepare() async -> Bool
    func analyze(audioWindow: AudioSampleWindow) async -> ChordDetectionResult?
}

extension BasicPitchChordAnalyzer: ChordAnalyzing {}
