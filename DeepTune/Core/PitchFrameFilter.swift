import Foundation

/// Decides which raw pitch readings the tuner trusts.
///
/// The detector reports a pitch and an amplitude for every buffer, including
/// noise, pluck transients and harmonics. This gates on signal level, ignores
/// the first moments of a pluck, folds harmonics back onto the Auto target and
/// rejects implausible jumps. It holds no audio, so recorded or synthetic
/// readings run through exactly the rules the live tuner uses.
nonisolated struct PitchFrameFilter {
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

    /// Auto passes the string it is tuning, so harmonics can be folded onto it;
    /// Manual passes nil and takes readings as they come.
    mutating func setTrackingTargetFrequency(_ frequency: Float?) {
        trackingTargetFrequency = frequency
        lastAcceptedPitch = 0.0
        lastAcceptedAt = nil
        resetAutoTrackingState()
    }

    /// Returns the frame to publish: an accepted pitch, a short hold of the last
    /// accepted one, or an empty frame for silence.
    mutating func process(pitch: Float, amp: Float, now: Date) -> PitchData {
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
            return PitchData()
        }

        // Ignore the first short transient right after signal opens.
        if let signalOpenedAt, now.timeIntervalSince(signalOpenedAt) < transientIgnoreDuration {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                return PitchData()
            } else {
                return rejectedFrameFallback(now: now)
            }
        }

        guard let resolved = resolvePitchCandidate(rawPitch: pitch) else {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                return PitchData()
            } else {
                return rejectedFrameFallback(now: now)
            }
        }

        if isUnstableHarmonicJump(newPitch: resolved.pitch, now: now) {
            if isTargetedTracking {
                registerAutoTrackingMissIfNeeded()
                return PitchData()
            } else {
                return rejectedFrameFallback(now: now)
            }
        }

        if let centsFromTarget = resolved.centsFromTarget {
            updateAutoTrackingState(absTargetCents: abs(centsFromTarget))
        } else {
            resetAutoTrackingState()
        }

        lastAcceptedPitch = resolved.pitch
        lastAcceptedAt = now

        return PitchData(pitch: resolved.pitch, amplitude: smoothedAmplitude)
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

    private func rejectedFrameFallback(now: Date) -> PitchData {
        guard lastAcceptedPitch > 0,
              let lastAcceptedAt,
              now.timeIntervalSince(lastAcceptedAt) <= rejectionHoldDuration else {
            return PitchData()
        }

        return PitchData(pitch: lastAcceptedPitch, amplitude: max(smoothedAmplitude * 0.65, 0.005))
    }

    private func resolvedTrackablePitchBounds(isTargetedTracking: Bool) -> ClosedRange<Float> {
        if isTargetedTracking {
            return autoMinTrackablePitch...autoMaxTrackablePitch
        }
        return manualMinTrackablePitch...manualMaxTrackablePitch
    }

    private mutating func updateAutoTrackingState(absTargetCents: Float) {
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

    private mutating func registerAutoTrackingMissIfNeeded() {
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

    private mutating func resetAutoTrackingState() {
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
}

/// One detector reading as the tuner publishes it; zero pitch means silence.
nonisolated struct PitchData: Sendable {
    var pitch: Float = 0.0
    var amplitude: Float = 0.0
}
