import Accelerate

/// Finds the fundamental frequency of a block of audio with the YIN method
/// (de Cheveigné & Kawahara, 2002).
///
/// YIN measures how well the signal matches itself shifted by each candidate
/// period, rather than looking for spectral peaks. A plucked string repeats
/// its own waveform closely, and the first shift that matches is the
/// fundamental even when the second harmonic is louder, which is how a phone
/// microphone hears a low E.
nonisolated struct YINPitchDetector {
    struct Configuration: Sendable {
        var sampleRate: Double
        /// The range the tuner accepts; PitchFrameFilter drops anything outside it.
        var minimumFrequency: Double = 30
        var maximumFrequency: Double = 1800
        /// Samples compared at each shift. Longer averages out more noise but
        /// smears a changing pitch.
        var windowSize = 2048
        /// A shift counts as a period once the normalised difference drops below
        /// this. Without such a dip the block is treated as unpitched, so noise
        /// and the last moments of a decay give no reading at all.
        var threshold: Float = 0.2
    }

    struct Reading: Sendable, Equatable {
        /// Zero when no period was found.
        let frequency: Float
        /// The normalised difference at the chosen period: 0 for a perfectly
        /// periodic signal, around 1 for noise.
        let aperiodicity: Float
    }

    let configuration: Configuration
    private let minimumLag: Int
    private let maximumLag: Int
    private var correlation: [Float]
    private var difference: [Float]

    /// Samples one detection reads, ending with the newest sample.
    var requiredSampleCount: Int { configuration.windowSize + maximumLag }

    init(configuration: Configuration) {
        self.configuration = configuration
        minimumLag = max(2, Int((configuration.sampleRate / configuration.maximumFrequency).rounded(.down)))
        maximumLag = Int((configuration.sampleRate / configuration.minimumFrequency).rounded(.up))
        correlation = [Float](repeating: 0, count: maximumLag + 1)
        difference = [Float](repeating: 0, count: maximumLag + 1)
    }

    /// Analyses the newest `requiredSampleCount` samples. Shorter input gives no reading.
    mutating func detect(_ samples: UnsafeBufferPointer<Float>) -> Reading {
        let needed = requiredSampleCount
        guard let base = samples.baseAddress, samples.count >= needed else {
            return Reading(frequency: 0, aperiodicity: 1)
        }
        let signal = base + (samples.count - needed)
        let window = configuration.windowSize
        let lagCount = maximumLag + 1

        // c(τ) = Σ x[j]·x[j+τ] for every lag in one correlation pass.
        correlation.withUnsafeMutableBufferPointer { output in
            vDSP_conv(signal, 1, signal, 1, output.baseAddress!, 1, vDSP_Length(lagCount), vDSP_Length(window))
        }

        // d(τ) = Σ (x[j] - x[j+τ])² = e(0) + e(τ) - 2c(τ), where e(τ) is the energy
        // of the window starting at τ, updated as the window slides.
        let headEnergy = Double(correlation[0])
        var shiftedEnergy = headEnergy
        difference[0] = 0
        for lag in 1..<lagCount {
            let leaving = Double(signal[lag - 1])
            let entering = Double(signal[lag - 1 + window])
            shiftedEnergy += entering * entering - leaving * leaving
            difference[lag] = Float(max(0, headEnergy + shiftedEnergy - 2 * Double(correlation[lag])))
        }

        // Cumulative mean normalisation: d'(τ) = d(τ)·τ / Σ d(1...τ). It stays near 1
        // for small shifts, so the zero difference at τ = 0 is never mistaken for a period.
        guard headEnergy > 1e-10 else { return Reading(frequency: 0, aperiodicity: 1) }
        var runningSum: Double = 0
        difference[0] = 1
        for lag in 1..<lagCount {
            runningSum += Double(difference[lag])
            difference[lag] = runningSum > 0 ? Float(Double(difference[lag]) * Double(lag) / runningSum) : 1
        }

        // The first dip under the threshold, followed down to its bottom. Taking the
        // first rather than the deepest is what keeps YIN off sub-harmonics.
        var lag = minimumLag
        while lag < lagCount, difference[lag] >= configuration.threshold {
            lag += 1
        }
        guard lag < lagCount else { return Reading(frequency: 0, aperiodicity: difference[minimumLag...].min() ?? 1) }
        while lag + 1 < lagCount, difference[lag + 1] < difference[lag] {
            lag += 1
        }

        let period = refinedLag(lag)
        return Reading(frequency: Float(configuration.sampleRate / period), aperiodicity: difference[lag])
    }

    /// The bottom of a parabola through the dip and its neighbours: periods fall
    /// between whole samples, and at 48 kHz one sample of lag is about 3 cents at 82 Hz.
    private func refinedLag(_ lag: Int) -> Double {
        guard lag > minimumLag, lag + 1 < difference.count else { return Double(lag) }
        let left = Double(difference[lag - 1])
        let centre = Double(difference[lag])
        let right = Double(difference[lag + 1])
        let curvature = left - 2 * centre + right
        guard curvature > 0 else { return Double(lag) }
        let offset = 0.5 * (left - right) / curvature
        return Double(lag) + max(-0.5, min(0.5, offset))
    }
}
