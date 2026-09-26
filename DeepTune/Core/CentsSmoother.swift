import Foundation

/// Blend factor for an exponential moving average that settles with
/// `timeConstant` seconds regardless of how often samples arrive.
nonisolated func smoothingFactor(elapsed: TimeInterval, timeConstant: TimeInterval) -> Float {
    guard timeConstant > 0 else { return 1 }
    return Float(1 - exp(-max(0, elapsed) / timeConstant))
}

/// Turns noisy per-frame cents readings into a steady meter value.
///
/// Settings are in seconds, so the meter behaves the same whether frames
/// arrive at the phone's 11.7 Hz or at the 60 Hz the synthetic tests use.
/// A trimmed mean over a short window rejects harmonic spikes, an exponential
/// average settles the rest, and a rate limit caps implausibly fast moves.
nonisolated struct CentsSmoother {
    struct Configuration: Sendable {
        /// Readings younger than this feed the trimmed mean...
        var window: TimeInterval
        /// ...but never fewer than this many, because rejecting a spike takes
        /// several clean readings, and at 11.7 Hz the window alone holds two.
        var minimumSamples: Int
        /// Settling time while the reading is near the meter value.
        var timeConstant: TimeInterval
        /// Slower settling for big jumps, which are usually harmonics or noise.
        var farTimeConstant: TimeInterval
        var farThresholdCents: Float
        /// Maximum movement in cents per second near centre, and the faster
        /// limits allowed once the meter is already far out.
        var rateLimit: Float
        var midRateLimit: Float
        var midRateFromCents: Float
        var farRateLimit: Float
        var farRateFromCents: Float

        // Derived from the per-event values tuned on device, where the tuner
        // received about 23 readings a second: blend 0.2 and 0.08, median of 5.
        static let standard = Configuration(
            window: 0.21,
            minimumSamples: 5,
            timeConstant: 0.19,
            farTimeConstant: 0.51,
            farThresholdCents: 110,
            rateLimit: 120,
            midRateLimit: 180,
            midRateFromCents: 90,
            farRateLimit: 320,
            farRateFromCents: 300
        )

        func rateLimit(atCents cents: Float) -> Float {
            let distance = abs(cents)
            if distance > farRateFromCents { return farRateLimit }
            if distance > midRateFromCents { return midRateLimit }
            return rateLimit
        }
    }

    private(set) var value: Float = 0
    private let configuration: Configuration
    private var samples: [(time: Date, cents: Float)] = []

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    var hasSamples: Bool { !samples.isEmpty }

    /// Clears the reading history. The meter value stays where it is so the
    /// needle doesn't jump; pass a value to move it as well.
    mutating func reset(to value: Float? = nil) {
        samples.removeAll()
        if let value {
            self.value = value
        }
    }

    @discardableResult
    mutating func add(_ cents: Float, at time: Date, elapsed: TimeInterval) -> Float {
        samples.append((time, cents))
        while samples.count > configuration.minimumSamples,
              let oldest = samples.first,
              time.timeIntervalSince(oldest.time) > configuration.window {
            samples.removeFirst()
        }
        let center = Self.trimmedMean(of: samples.map(\.cents)) ?? cents

        let isFar = abs(center - value) > configuration.farThresholdCents
        let factor = smoothingFactor(
            elapsed: elapsed,
            timeConstant: isFar ? configuration.farTimeConstant : configuration.timeConstant
        )
        let target = value + (center - value) * factor

        let maxStep = Float(elapsed) * configuration.rateLimit(atCents: value)
        value += max(-maxStep, min(maxStep, target - value))
        return value
    }

    /// Mean of the middle half. Unlike a median it doesn't shift a whole rank
    /// when one outlier enters a small window, which biased the meter by the
    /// full size of the reading jitter.
    static func trimmedMean(of values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let trim = sorted.count >= 4 ? max(1, sorted.count / 4) : 0
        let kept = sorted[trim..<(sorted.count - trim)]
        return kept.reduce(0, +) / Float(kept.count)
    }
}
