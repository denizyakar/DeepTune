import Foundation

struct TunerDiagnosticsReport {
    let scenarioName: String
    let peakCentsJump: Float
    let averageAbsoluteCents: Float
    let reachedSuccess: Bool
    let firstSuccessSecond: Double?
    
    var summaryLine: String {
        let successText = reachedSuccess ? "SUCCESS" : "NO_SUCCESS"
        let timeText = firstSuccessSecond.map { String(format: "%.2fs", $0) } ?? "n/a"
        return "\(scenarioName): \(successText), peakJump=\(String(format: "%.1f", peakCentsJump))c, avgAbs=\(String(format: "%.1f", averageAbsoluteCents))c, firstSuccess=\(timeText)"
    }
}

struct ManualTunerDiagnosticsReport {
    let scenarioName: String
    let targetFullName: String
    let peakJumpCentsPerFrame: Float
    let p95JumpCentsPerFrame: Float
    let averageJumpCentsPerFrame: Float
    let noteFlipCount: Int
    let largeOutlierCount: Int
    let signalDropCount: Int
    let topJumpEvents: [String]
    
    var summaryLine: String {
        "\(scenarioName) \(targetFullName): peakJump=\(String(format: "%.1f", peakJumpCentsPerFrame))c/frame, p95Jump=\(String(format: "%.1f", p95JumpCentsPerFrame))c/frame, avgJump=\(String(format: "%.2f", averageJumpCentsPerFrame))c/frame, flips=\(noteFlipCount), outliers=\(largeOutlierCount), signalDrops=\(signalDropCount)"
    }
}

enum ManualSignalProfile: String {
    case clean
    case harmonicStress
}

struct AutoValidationReport {
    let scenarioName: String
    let trialCount: Int
    let lockSuccessCount: Int
    let lockSuccessRate: Double
    let averageLockSeconds: Double
    let p95JumpCentsPerFrame: Float
    let falseLockCount: Int
    let signalDropRate: Double
    
    var summaryLine: String {
        "\(scenarioName): lockRate=\(String(format: "%.1f", lockSuccessRate * 100))%, avgLock=\(String(format: "%.2f", averageLockSeconds))s, p95Jump=\(String(format: "%.1f", p95JumpCentsPerFrame))c/frame, falseLocks=\(falseLockCount), signalDropRate=\(String(format: "%.1f", signalDropRate * 100))%"
    }
}

enum TunerDiagnostics {
    static func runSyntheticTargetScenario(
        target: Note,
        duration: Double = 8.0,
        frameRate: Double = 50.0
    ) -> TunerDiagnosticsReport {
        let viewModel = TunerViewModel()
        viewModel.setTargetNote(target)
        
        let dt = 1.0 / frameRate
        let frameCount = Int(duration * frameRate)
        var now = Date(timeIntervalSince1970: 0)
        
        var previousCents = viewModel.autoCentsDistance
        var peakJump: Float = 0
        var cumulativeAbsCents: Float = 0
        var firstSuccessSecond: Double?
        
        for frame in 0..<frameCount {
            let t = Double(frame) * dt
            let signal = syntheticPluckSignal(time: t, targetFrequency: Float(target.frequency))
            
            #if DEBUG
            viewModel.debugInjectFrame(pitch: signal.pitch, amplitude: signal.amplitude, timestamp: now)
            #endif
            
            let currentCents = viewModel.autoCentsDistance
            peakJump = max(peakJump, abs(currentCents - previousCents))
            cumulativeAbsCents += abs(currentCents)
            previousCents = currentCents
            
            if firstSuccessSecond == nil, viewModel.isTuningSuccessful {
                firstSuccessSecond = t
            }
            
            now = now.addingTimeInterval(dt)
        }
        
        let averageAbsCents = cumulativeAbsCents / Float(max(1, frameCount))
        return TunerDiagnosticsReport(
            scenarioName: "Synthetic-\(target.fullName)",
            peakCentsJump: peakJump,
            averageAbsoluteCents: averageAbsCents,
            reachedSuccess: firstSuccessSecond != nil,
            firstSuccessSecond: firstSuccessSecond
        )
    }
    
    static func runManualJitterScenario(
        target: Note,
        duration: Double = 10.0,
        frameRate: Double = 60.0,
        profile: ManualSignalProfile = .harmonicStress
    ) -> ManualTunerDiagnosticsReport {
        let viewModel = TunerViewModel()
        viewModel.setActiveMode(.manual)
        viewModel.setTargetNote(nil)
        
        let dt = 1.0 / frameRate
        let frameCount = Int(duration * frameRate)
        var now = Date(timeIntervalSince1970: 0)
        
        var previousCents = viewModel.manualCentsDistance
        var jumps: [Float] = []
        var noteFlipCount = 0
        var outlierCount = 0
        var signalDropCount = 0
        var topJumpEvents: [(jump: Float, line: String)] = []
        
        for frame in 0..<frameCount {
            let t = Double(frame) * dt
            let signal = syntheticManualSignal(time: t, targetFrequency: Float(target.frequency), profile: profile)
            
            #if DEBUG
            viewModel.debugInjectFrame(pitch: signal.pitch, amplitude: signal.amplitude, timestamp: now)
            #endif
            
            if !viewModel.isSignalDetected {
                signalDropCount += 1
            }
            
            if let detected = viewModel.detectedNote, "\(detected.name)\(detected.octave)" != target.fullName {
                noteFlipCount += 1
            }
            
            let current = viewModel.manualCentsDistance
            let jump = abs(current - previousCents)
            jumps.append(jump)
            previousCents = current
            
            if abs(current) > 35.0 {
                outlierCount += 1
            }
            
            let eventLine = String(
                format: "t=%.2fs jump=%.1f cents rawPitch=%.2fHz manual=%.1f",
                t,
                jump,
                signal.pitch,
                current
            )
            pushTopJump(&topJumpEvents, jump: jump, line: eventLine, keep: 5)
            
            now = now.addingTimeInterval(dt)
        }
        
        let averageJump = jumps.reduce(0, +) / Float(max(1, jumps.count))
        let p95Jump = percentile(jumps, p: 0.95)
        let peakJump = jumps.max() ?? 0
        
        return ManualTunerDiagnosticsReport(
            scenarioName: "ManualJitterScenario[\(profile.rawValue)]",
            targetFullName: target.fullName,
            peakJumpCentsPerFrame: peakJump,
            p95JumpCentsPerFrame: p95Jump,
            averageJumpCentsPerFrame: averageJump,
            noteFlipCount: noteFlipCount,
            largeOutlierCount: outlierCount,
            signalDropCount: signalDropCount,
            topJumpEvents: topJumpEvents.sorted(by: { $0.jump > $1.jump }).map(\.line)
        )
    }
    
    static func runAutoValidationSuite(
        instrument: Instrument = InstrumentCatalog.guitar6,
        timeoutSeconds: Double = 8.0,
        frameRate: Double = 60.0
    ) -> AutoValidationReport {
        let notes = instrument.defaultTuning.notes
        let dt = 1.0 / frameRate
        let frameCount = Int(timeoutSeconds * frameRate)
        
        var lockSuccessCount = 0
        var lockTimes: [Double] = []
        var jumpSamples: [Float] = []
        var signalDropFrames = 0
        var totalFrames = 0
        var falseLockCount = 0
        
        for note in notes {
            let vm = TunerViewModel(instrument: instrument)
            vm.setActiveMode(.auto)
            vm.setTargetNote(note)
            
            var now = Date(timeIntervalSince1970: 0)
            var previousCents: Float = vm.autoCentsDistance
            var firstLockSecond: Double?
            
            for frame in 0..<frameCount {
                let t = Double(frame) * dt
                let signal = syntheticPluckSignal(time: t, targetFrequency: Float(note.frequency))
                
                #if DEBUG
                vm.debugInjectFrame(pitch: signal.pitch, amplitude: signal.amplitude, timestamp: now)
                #endif
                
                if signal.pitch > 0, !vm.isTargetSignalDetected {
                    signalDropFrames += 1
                }
                totalFrames += 1
                
                let current = vm.autoCentsDistance
                jumpSamples.append(abs(current - previousCents))
                previousCents = current
                
                if firstLockSecond == nil, vm.isTuningSuccessful {
                    firstLockSecond = t
                }
                
                now = now.addingTimeInterval(dt)
            }
            
            if let lockTime = firstLockSecond {
                lockSuccessCount += 1
                lockTimes.append(lockTime)
            }
            
            falseLockCount += runAutoFalseLockTrial(target: note, instrument: instrument, frameRate: frameRate)
        }
        
        let successRate = Double(lockSuccessCount) / Double(max(1, notes.count))
        let averageLock = lockTimes.isEmpty ? timeoutSeconds : (lockTimes.reduce(0, +) / Double(lockTimes.count))
        let p95Jump = percentile(jumpSamples, p: 0.95)
        let signalDropRate = Double(signalDropFrames) / Double(max(1, totalFrames))
        
        return AutoValidationReport(
            scenarioName: "AutoValidation[\(instrument.name)]",
            trialCount: notes.count,
            lockSuccessCount: lockSuccessCount,
            lockSuccessRate: successRate,
            averageLockSeconds: averageLock,
            p95JumpCentsPerFrame: p95Jump,
            falseLockCount: falseLockCount,
            signalDropRate: signalDropRate
        )
    }
    
    // Models repeated plucks: transient spike -> settle -> decay -> brief silence.
    private static func syntheticPluckSignal(time t: Double, targetFrequency: Float) -> (pitch: Float, amplitude: Float) {
        let pluckPeriod = 0.55
        let local = t.truncatingRemainder(dividingBy: pluckPeriod)
        let decay = exp(-local * 5.2)
        
        // Early transient deliberately includes stronger disturbance and slight octave tendency.
        let transientNoise = local < 0.06 ? Float(sin(t * 97.0)) * 95.0 : Float(sin(t * 43.0)) * 10.0
        let centsOffset = transientNoise + Float(sin(t * 8.5)) * 2.2
        let frequency = targetFrequency * pow(2.0, centsOffset / 1200.0)
        
        let amplitudeBase = Float(0.02 + (0.08 * decay))
        let amplitudeNoise = Float(sin(t * 31.0)) * 0.004
        let amplitude = max(0, amplitudeBase + amplitudeNoise)
        
        // Add short silent gap to emulate real pluck spacing.
        if local > 0.44 {
            return (pitch: 0, amplitude: 0)
        }
        
        return (pitch: frequency, amplitude: amplitude)
    }

    private static func runAutoFalseLockTrial(target: Note, instrument: Instrument, frameRate: Double) -> Int {
        let wrongFrequencies: [Float] = [
            Float(target.frequency) * pow(2.0, 100.0 / 1200.0), // near-note mismatch
            Float(target.frequency) * 0.75 // 3/4 ratio trap (e.g. E4 <-> B3 class issue)
        ]
        
        for (idx, wrongFrequency) in wrongFrequencies.enumerated() {
            let vm = TunerViewModel(instrument: instrument)
            vm.setActiveMode(.auto)
            vm.setTargetNote(target)
            
            let dt = 1.0 / frameRate
            let frameCount = Int(5.0 * frameRate)
            var now = Date(timeIntervalSince1970: 500 + Double(idx))
            
            for frame in 0..<frameCount {
                let t = Double(frame) * dt
                let local = t.truncatingRemainder(dividingBy: 0.42)
                let decay = exp(-local * 5.0)
                let amplitude = Float(0.03 + 0.03 * decay)
                let jitterCents = Float(sin(t * 41.0)) * 4.0
                let pitch = wrongFrequency * pow(2.0, jitterCents / 1200.0)
                
                #if DEBUG
                vm.debugInjectFrame(pitch: pitch, amplitude: amplitude, timestamp: now)
                #endif
                
                if vm.isTuningSuccessful {
                    return 1
                }
                now = now.addingTimeInterval(dt)
            }
        }
        
        return 0
    }
    
    // Generates deterministic near-target jitter with occasional harmonic spikes and dropouts.
    private static func syntheticManualSignal(
        time t: Double,
        targetFrequency: Float,
        profile: ManualSignalProfile
    ) -> (pitch: Float, amplitude: Float) {
        let baseJitter = (sin(t * 27.0) * 0.55) + (sin(t * 71.0) * 0.35) + (sin(t * 133.0) * 0.1)
        var centsOffset = Float(baseJitter) * (profile == .clean ? 4.0 : 9.0)
        
        // Short transient bursts that emulate pick attacks.
        let attackCycle = t.truncatingRemainder(dividingBy: 0.42)
        if attackCycle < 0.03, profile == .harmonicStress {
            centsOffset += Float(sin(t * 250.0)) * 58.0
        }
        
        var frequency = targetFrequency * pow(2.0, centsOffset / 1200.0)
        
        // Occasional harmonic confusion frame.
        let harmonicCycle = t.truncatingRemainder(dividingBy: 1.35)
        if profile == .harmonicStress, harmonicCycle > 0.04 && harmonicCycle < 0.055 {
            frequency *= 2.0
        }
        
        // Deterministic dropout window.
        let dropoutCycle = t.truncatingRemainder(dividingBy: 2.8)
        if profile == .harmonicStress, dropoutCycle > 2.66 && dropoutCycle < 2.74 {
            return (pitch: 0, amplitude: 0)
        }
        
        let amplitudeBase: Float = profile == .clean ? 0.045 : 0.028
        let amplitudeSwing: Float = profile == .clean ? 0.006 : 0.012
        let amplitude = amplitudeBase + (amplitudeSwing * abs(Float(sin(t * 11.0))))
        return (pitch: frequency, amplitude: amplitude)
    }
    
    private static func percentile(_ values: [Float], p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let clampedP = max(0.0, min(1.0, p))
        let idx = Int(Double(sorted.count - 1) * clampedP)
        return sorted[idx]
    }
    
    private static func pushTopJump(
        _ storage: inout [(jump: Float, line: String)],
        jump: Float,
        line: String,
        keep: Int
    ) {
        storage.append((jump: jump, line: line))
        storage.sort { $0.jump > $1.jump }
        if storage.count > keep {
            storage.removeSubrange(keep..<storage.count)
        }
    }
}
