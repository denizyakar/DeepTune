import Foundation
import CoreML

struct ChordDetectionResult {
    let name: String
    let rootName: String
    let confidence: Double
    let observedNoteNames: [String]
    let bassNoteName: String?
    let candidates: [ChordDetectionCandidate]
}

struct ChordDetectionCandidate {
    let name: String
    let rootName: String
    let confidence: Double
    let matchedCoverage: Double
    let expectedCoverage: Double
}

/// Actor-isolated because the model is loaded lazily and then read from several
/// contexts. A `lazy var` would race here: the view asks whether the model is
/// available while an analysis task may already be loading it.
actor BasicPitchChordAnalyzer {
    static let shared = BasicPitchChordAnalyzer()

    private struct ChordTemplate {
        let suffix: String
        let intervals: [Int]
        let rarityWeight: Double
    }

    private let audioSampleRate: Double = 22_050.0
    private let expectedAudioSampleCount = 43_844
    private let noteBins = 88
    private let baseMIDINote = 21 // A0

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private let templates: [ChordTemplate] = [
        ChordTemplate(suffix: "", intervals: [0, 4, 7], rarityWeight: 0.00),
        ChordTemplate(suffix: "m", intervals: [0, 3, 7], rarityWeight: 0.00),
        ChordTemplate(suffix: "5", intervals: [0, 7], rarityWeight: 0.10),
        ChordTemplate(suffix: "sus2", intervals: [0, 2, 7], rarityWeight: 0.08),
        ChordTemplate(suffix: "sus4", intervals: [0, 5, 7], rarityWeight: 0.08),
        ChordTemplate(suffix: "dim", intervals: [0, 3, 6], rarityWeight: 0.14),
        ChordTemplate(suffix: "aug", intervals: [0, 4, 8], rarityWeight: 0.16),
        ChordTemplate(suffix: "6", intervals: [0, 4, 7, 9], rarityWeight: 0.12),
        ChordTemplate(suffix: "m6", intervals: [0, 3, 7, 9], rarityWeight: 0.14),
        ChordTemplate(suffix: "7", intervals: [0, 4, 7, 10], rarityWeight: 0.00),
        ChordTemplate(suffix: "maj7", intervals: [0, 4, 7, 11], rarityWeight: 0.06),
        ChordTemplate(suffix: "m7", intervals: [0, 3, 7, 10], rarityWeight: 0.00),
        ChordTemplate(suffix: "mMaj7", intervals: [0, 3, 7, 11], rarityWeight: 0.28),
        ChordTemplate(suffix: "add9", intervals: [0, 2, 4, 7], rarityWeight: 0.18),
        ChordTemplate(suffix: "madd9", intervals: [0, 2, 3, 7], rarityWeight: 0.20),
        ChordTemplate(suffix: "9", intervals: [0, 2, 4, 7, 10], rarityWeight: 0.16),
        ChordTemplate(suffix: "maj9", intervals: [0, 2, 4, 7, 11], rarityWeight: 0.18),
        ChordTemplate(suffix: "m9", intervals: [0, 2, 3, 7, 10], rarityWeight: 0.16),
        ChordTemplate(suffix: "11", intervals: [0, 4, 7, 10, 5], rarityWeight: 0.18),
        ChordTemplate(suffix: "m11", intervals: [0, 3, 7, 10, 5], rarityWeight: 0.18),
        ChordTemplate(suffix: "maj11", intervals: [0, 4, 7, 11, 5], rarityWeight: 0.24),
        ChordTemplate(suffix: "13", intervals: [0, 4, 7, 10, 9], rarityWeight: 0.22),
        ChordTemplate(suffix: "m13", intervals: [0, 3, 7, 10, 9], rarityWeight: 0.24),
        ChordTemplate(suffix: "maj13", intervals: [0, 4, 7, 11, 9], rarityWeight: 0.26),
        ChordTemplate(suffix: "7sus4", intervals: [0, 5, 7, 10], rarityWeight: 0.16),
        ChordTemplate(suffix: "dim7", intervals: [0, 3, 6, 9], rarityWeight: 0.20),
        ChordTemplate(suffix: "m7b5", intervals: [0, 3, 6, 10], rarityWeight: 0.16)
    ]

    private var model: MLModel?
    private var didAttemptLoad = false

    private init() {}

    /// Loads the model if it has not been loaded yet and reports whether it is
    /// usable. Loading takes a noticeable moment, so callers should await this
    /// off the main actor (e.g. from `task()`) instead of reading it while a
    /// view body is being evaluated.
    @discardableResult
    func prepare() -> Bool {
        if !didAttemptLoad {
            didAttemptLoad = true
            model = Self.loadModel()
        }
        return model != nil
    }

    func analyze(audioWindow: AudioSampleWindow) -> ChordDetectionResult? {
        prepare()
        guard let model else { return nil }

        guard let preparedSamples = prepareAudioInput(
            samples: audioWindow.samples,
            sourceSampleRate: audioWindow.sampleRate
        ) else {
            return nil
        }

        do {
            let input = try makeInputFeatureProvider(model: model, samples: preparedSamples)
            let output = try model.prediction(from: input)

            guard let extractedWeights = extractPitchAndNoteWeights(from: output) else {
                return nil
            }

            return decodeChord(
                fromPitchClassWeights: extractedWeights.pitchClassWeights,
                noteBinWeights: extractedWeights.noteBinWeights
            )
        } catch {
            return nil
        }
    }

    private static func loadModel() -> MLModel? {
        let config = MLModelConfiguration()

        if let compiledURL = Bundle.main.url(forResource: "nmp", withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: compiledURL, configuration: config)
        }

        if let packageURL = Bundle.main.url(forResource: "nmp", withExtension: "mlpackage") {
            let compiledURL = try? MLModel.compileModel(at: packageURL)
            if let compiledURL {
                return try? MLModel(contentsOf: compiledURL, configuration: config)
            }
        }

        return nil
    }

    private func prepareAudioInput(samples: [Float], sourceSampleRate: Double) -> [Float]? {
        guard !samples.isEmpty, sourceSampleRate > 0 else { return nil }

        let resampled: [Float]
        if abs(sourceSampleRate - audioSampleRate) < 0.1 {
            resampled = samples
        } else {
            resampled = resampleLinear(samples: samples, from: sourceSampleRate, to: audioSampleRate)
        }

        guard !resampled.isEmpty else { return nil }

        if resampled.count >= expectedAudioSampleCount {
            return Array(resampled.suffix(expectedAudioSampleCount))
        }

        var padded = [Float](repeating: 0.0, count: expectedAudioSampleCount - resampled.count)
        padded.append(contentsOf: resampled)
        return padded
    }

    private func resampleLinear(samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        let ratio = sourceRate / targetRate
        let outputCount = Int(Double(samples.count) / ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0.0, count: outputCount)
        for outputIndex in 0..<outputCount {
            let sourcePosition = Double(outputIndex) * ratio
            let leftIndex = Int(floor(sourcePosition))
            let rightIndex = min(leftIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(leftIndex))

            let left = samples[leftIndex]
            let right = samples[rightIndex]
            output[outputIndex] = left + ((right - left) * fraction)
        }

        return output
    }

    private func makeInputFeatureProvider(model: MLModel, samples: [Float]) throws -> MLFeatureProvider {
        guard let firstInput = model.modelDescription.inputDescriptionsByName.first else {
            throw NSError(domain: "BasicPitchChordAnalyzer", code: 1)
        }

        let inputName = firstInput.key
        guard let inputConstraint = firstInput.value.multiArrayConstraint else {
            throw NSError(domain: "BasicPitchChordAnalyzer", code: 2)
        }

        let shape = inputConstraint.shape.map { $0.intValue }
        guard !shape.isEmpty else {
            throw NSError(domain: "BasicPitchChordAnalyzer", code: 3)
        }

        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: inputConstraint.dataType)
        fillInputArray(array, samples: samples)

        return try MLDictionaryFeatureProvider(dictionary: [inputName: array])
    }

    private func fillInputArray(_ array: MLMultiArray, samples: [Float]) {
        let strides = array.strides.map { $0.intValue }
        let shape = array.shape.map { $0.intValue }
        let timeAxis = inferTimeAxis(for: shape)
        let count = min(samples.count, shape[timeAxis])
        var indices = [Int](repeating: 0, count: shape.count)

        for i in 0..<count {
            indices[timeAxis] = i
            let offset = offsetFor(indices: indices, strides: strides)
            setMultiArrayValue(array, offset: offset, value: Double(samples[i]))
        }
    }

    private func inferTimeAxis(for shape: [Int]) -> Int {
        if let exactMatch = shape.firstIndex(of: expectedAudioSampleCount) {
            return exactMatch
        }

        // Basic Pitch input is [1, 43844, 1], but keep a robust fallback for future model variants.
        var bestAxis = 0
        var bestSize = -1
        for (axis, size) in shape.enumerated() where size > bestSize {
            bestAxis = axis
            bestSize = size
        }
        return bestAxis
    }

    private func offsetFor(indices: [Int], strides: [Int]) -> Int {
        var offset = 0
        for (index, stride) in zip(indices, strides) {
            offset += index * stride
        }
        return offset
    }

    private func setMultiArrayValue(_ array: MLMultiArray, offset: Int, value: Double) {
        switch array.dataType {
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            pointer[offset] = value
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            pointer[offset] = Float(value)
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: array.count)
            pointer[offset] = floatToFloat16(Float(value))
        default:
            break
        }
    }

    private func floatToFloat16(_ value: Float) -> UInt16 {
        let bitPattern = value.bitPattern
        let sign = UInt16((bitPattern >> 16) & 0x8000)
        var exponent = Int((bitPattern >> 23) & 0xFF) - 127 + 15
        var mantissa = UInt16((bitPattern >> 13) & 0x03FF)

        if exponent <= 0 {
            exponent = 0
            mantissa = 0
        } else if exponent >= 31 {
            exponent = 31
            mantissa = 0
        }

        return sign | UInt16(exponent << 10) | mantissa
    }

    private func extractPitchAndNoteWeights(from output: MLFeatureProvider) -> (pitchClassWeights: [Double], noteBinWeights: [Double])? {
        var combinedWeights = [Double](repeating: 0.0, count: noteBins)
        var combinedEnergy = 0.0

        for featureName in output.featureNames {
            guard let featureValue = output.featureValue(for: featureName),
                  featureValue.type == .multiArray,
                  let array = featureValue.multiArrayValue else {
                continue
            }

            guard let noteWeights = aggregateNoteWeights(from: array) else { continue }
            let outputWeight = outputConfidenceWeight(for: featureName)
            guard outputWeight > 0 else { continue }

            let totalEnergy = noteWeights.reduce(0, +) * outputWeight
            guard totalEnergy > 0 else { continue }

            combinedEnergy += totalEnergy
            for noteBin in 0..<noteBins {
                combinedWeights[noteBin] += noteWeights[noteBin] * outputWeight
            }
        }

        guard combinedEnergy > 0.01 else {
            return nil
        }

        var pitchClassWeights = [Double](repeating: 0.0, count: 12)
        for (noteBin, weight) in combinedWeights.enumerated() {
            let midi = baseMIDINote + noteBin
            let pitchClass = ((midi % 12) + 12) % 12
            pitchClassWeights[pitchClass] += weight
        }

        return (pitchClassWeights, combinedWeights)
    }

    private func outputConfidenceWeight(for featureName: String) -> Double {
        // In nmp, Identity_1 behaves as sustained note activation.
        // Identity_2 tends to be onset-heavy/noisier for chord quality.
        let lowered = featureName.lowercased()
        if lowered.contains("identity_1") {
            return 1.0
        }
        if lowered.contains("identity_2") {
            return 0.35
        }
        return 0.0
    }

    private func aggregateNoteWeights(from array: MLMultiArray) -> [Double]? {
        let shape = array.shape.map { $0.intValue }
        guard let noteAxis = shape.firstIndex(of: noteBins) else { return nil }

        let strides = array.strides.map { $0.intValue }
        let candidateTimeAxes = shape.indices.filter { $0 != noteAxis && shape[$0] > 1 }
        let timeAxis = candidateTimeAxes.max { shape[$0] < shape[$1] }
        let timeCount = timeAxis.map { shape[$0] } ?? 1
        let maxFrameIndex = max(1, timeCount - 1)

        var perFrameWeights = [[Double]]()
        perFrameWeights.reserveCapacity(timeCount)
        var frameEnergies = [Double]()
        frameEnergies.reserveCapacity(timeCount)

        for frame in 0..<timeCount {
            var indices = [Int](repeating: 0, count: shape.count)
            if let timeAxis {
                indices[timeAxis] = frame
            }

            var rawFrameWeights = [Double](repeating: 0.0, count: noteBins)
            for noteBin in 0..<noteBins {
                indices[noteAxis] = noteBin
                rawFrameWeights[noteBin] = max(0.0, readMultiArrayValue(array, offset: offsetFor(indices: indices, strides: strides)))
            }

            // Basic Pitch outputs can carry a non-trivial baseline across all bins.
            // Remove it per-frame so chord decoding doesn't see every pitch class as "active".
            let baseline = percentile(of: rawFrameWeights, q: 0.72)
            var frameWeights = [Double](repeating: 0.0, count: noteBins)
            var frameEnergy = 0.0

            for noteBin in 0..<noteBins {
                let lifted = max(0.0, rawFrameWeights[noteBin] - baseline)
                let enhanced = lifted * lifted
                frameWeights[noteBin] = enhanced
                frameEnergy += enhanced
            }

            perFrameWeights.append(frameWeights)
            frameEnergies.append(frameEnergy)
        }

        guard let maxFrameEnergy = frameEnergies.max(), maxFrameEnergy > 0.0005 else { return nil }
        let activeEnergyThreshold = max(0.002, maxFrameEnergy * 0.22)

        var noteWeights = [Double](repeating: 0.0, count: noteBins)
        for frame in 0..<timeCount where frameEnergies[frame] >= activeEnergyThreshold {
            let timeWeight = 0.55 + (0.45 * (Double(frame) / Double(maxFrameIndex)))
            let frameWeights = perFrameWeights[frame]
            for noteBin in 0..<noteBins {
                noteWeights[noteBin] += frameWeights[noteBin] * timeWeight
            }
        }

        guard let maxNoteWeight = noteWeights.max(), maxNoteWeight > 0.001 else { return nil }
        let noiseFloor = maxNoteWeight * 0.08
        for noteBin in 0..<noteBins where noteWeights[noteBin] < noiseFloor {
            noteWeights[noteBin] = 0
        }

        return noteWeights
    }

    private func percentile(of values: [Double], q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clampedQ = min(1.0, max(0.0, q))
        let sorted = values.sorted()
        let position = Int(Double(sorted.count - 1) * clampedQ)
        return sorted[position]
    }

    private func readMultiArrayValue(_ array: MLMultiArray, offset: Int) -> Double {
        switch array.dataType {
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            return pointer[offset]
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return Double(pointer[offset])
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: array.count)
            return Double(float16ToFloat(pointer[offset]))
        default:
            return 0.0
        }
    }

    private func float16ToFloat(_ value: UInt16) -> Float {
        let sign = UInt32(value & 0x8000) << 16
        var exponent = Int((value >> 10) & 0x1F)
        var mantissa = UInt32(value & 0x03FF)

        if exponent == 0 {
            if mantissa == 0 {
                return Float(bitPattern: sign)
            }

            exponent = 1
            while (mantissa & 0x0400) == 0 {
                mantissa <<= 1
                exponent -= 1
            }
            mantissa &= 0x03FF
        } else if exponent == 31 {
            return Float(bitPattern: sign | 0x7F800000 | (mantissa << 13))
        }

        let floatExponent = UInt32(exponent - 15 + 127) << 23
        let floatMantissa = mantissa << 13
        return Float(bitPattern: sign | floatExponent | floatMantissa)
    }

    private func decodeChord(fromPitchClassWeights pitchClassWeights: [Double], noteBinWeights: [Double]) -> ChordDetectionResult? {
        let maxWeight = pitchClassWeights.max() ?? 0
        guard maxWeight > 0.001 else { return nil }

        let threshold = max(maxWeight * 0.14, 0.001)
        let rankedPitchClasses = pitchClassWeights.enumerated().sorted { $0.element > $1.element }
        var observed = rankedPitchClasses.filter { $0.element >= threshold }.map(\.offset)
        if observed.count < 2 {
            observed = Array(rankedPitchClasses.prefix(2).map(\.offset))
        }
        if observed.count > 5 {
            observed = Array(observed.prefix(5))
        }
        let observedSet = Set(observed)
        guard observedSet.count >= 2 else { return nil }
        let bassPitchClass = detectBassPitchClass(noteBinWeights: noteBinWeights, observedSet: observedSet)

        struct Match {
            let root: Int
            let suffix: String
            let score: Double
            let matchedWeight: Double
            let expected: Set<Int>
            let extraWeight: Double
            let complexityPenalty: Double
            let rarityWeight: Double
            let matchedCoverage: Double
            let expectedCoverage: Double
        }

        var matches: [Match] = []
        let totalWeight = pitchClassWeights.reduce(0, +)

        for root in 0..<12 {
            for template in templates {
                let expected = Set(template.intervals.map { (root + $0) % 12 })
                let matchedWeight = expected.reduce(0.0) { partial, pitchClass in
                    partial + pitchClassWeights[pitchClass]
                }
                let missingCount = expected.filter { !observedSet.contains($0) }.count
                let extraWeight = observedSet.subtracting(expected).reduce(0.0) { partial, pitchClass in
                    partial + pitchClassWeights[pitchClass]
                }
                let matchedCoverage = matchedWeight / max(1e-6, totalWeight)
                let expectedCoverage = Double(expected.intersection(observedSet).count) / Double(expected.count)

                let complexityPenalty = max(0, expected.count - 3)
                let sparseObservationPenalty: Double
                if observedSet.count <= 3 {
                    sparseObservationPenalty = Double(max(0, expected.count - observedSet.count)) * 1.25
                } else {
                    sparseObservationPenalty = 0
                }
                let rarityPenalty = template.rarityWeight * 1.10
                let score = (matchedWeight * 2.0) - (Double(missingCount) * 2.15) - (extraWeight * 1.10) - (Double(complexityPenalty) * 0.72) - sparseObservationPenalty - rarityPenalty
                matches.append(
                    Match(
                        root: root,
                        suffix: template.suffix,
                        score: score,
                        matchedWeight: matchedWeight,
                        expected: expected,
                        extraWeight: extraWeight,
                        complexityPenalty: Double(complexityPenalty),
                        rarityWeight: template.rarityWeight,
                        matchedCoverage: matchedCoverage,
                        expectedCoverage: expectedCoverage
                    )
                )
            }
        }

        let ranked = matches.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.expectedCoverage > rhs.expectedCoverage
            }
            return lhs.score > rhs.score
        }
        guard let best = ranked.first else { return nil }
        guard best.score > 0.45 else { return nil }
        let matchedCoverage = best.matchedCoverage
        let expectedCoverage = best.expectedCoverage
        guard matchedCoverage >= 0.44, expectedCoverage >= 0.52 else { return nil }

        var scoreGap = 3.0
        var ambiguityPenalty = 0.0
        var rootConflictPenalty = 0.0
        if ranked.count >= 2 {
            let second = ranked[1]
            scoreGap = best.score - second.score
            let normalizedTightness = max(0.0, min(1.0, 1.0 - (scoreGap / 2.4)))
            ambiguityPenalty = normalizedTightness * 0.24
            if second.root != best.root && scoreGap < 1.35 {
                rootConflictPenalty = 0.12
            }
        }

        let normalizedGap = max(0.0, min(1.0, scoreGap / 4.8))
        var bestConfidence = max(
            0.12,
            min(
                0.82,
                0.20
                    + (matchedCoverage * 0.33)
                    + (expectedCoverage * 0.26)
                    + (normalizedGap * 0.15)
                    - ((best.extraWeight / max(1e-6, totalWeight)) * 0.18)
                    - (best.complexityPenalty * 0.015)
                    - (best.rarityWeight * 0.09)
                    - ambiguityPenalty
                    - rootConflictPenalty
            )
        )
        if ranked.count >= 2 {
            let second = ranked[1]
            if second.root != best.root && second.matchedCoverage >= 0.82 && second.expectedCoverage >= 0.75 {
                bestConfidence = min(bestConfidence, 0.78)
            }
        }
        guard bestConfidence >= 0.18 else { return nil }

        let minimumCandidateScore = max(best.score - 9.0, 0.12)
        var topMatches = ranked
            .filter { match in
                match.score >= minimumCandidateScore
                    && match.matchedCoverage >= 0.30
                    && match.expectedCoverage >= 0.35
            }
            .prefix(5)
            .map { $0 }

        if topMatches.count < 3 {
            for match in ranked where !topMatches.contains(where: { $0.root == match.root && $0.suffix == match.suffix }) {
                guard match.matchedCoverage >= 0.22, match.expectedCoverage >= 0.28 else { continue }
                topMatches.append(match)
                if topMatches.count >= 5 { break }
            }
        }

        var candidates: [ChordDetectionCandidate] = []
        for match in topMatches {
            let scoreDelta = max(0.0, best.score - match.score)
            let closeness = max(0.0, min(1.0, 1.0 - (scoreDelta / 7.5)))
            let extraPenalty = (match.extraWeight / max(1e-6, totalWeight)) * 0.18
            let candidateConfidence = max(
                0.08,
                min(
                    0.93,
                    0.10
                        + (match.matchedCoverage * 0.38)
                        + (match.expectedCoverage * 0.28)
                        + (closeness * 0.18)
                        - extraPenalty
                        - (match.complexityPenalty * 0.016)
                        - (match.rarityWeight * 0.08)
                )
            )
            let chordName = chordLabel(root: match.root, suffix: match.suffix)
            candidates.append(
                ChordDetectionCandidate(
                    name: chordName,
                    rootName: noteNames[match.root],
                    confidence: candidateConfidence,
                    matchedCoverage: match.matchedCoverage,
                    expectedCoverage: match.expectedCoverage
                )
            )
        }

        if let primary = candidates.first {
            let hasStrongAlternateRoot = candidates.contains {
                $0.rootName != primary.rootName && $0.confidence >= (primary.confidence - 0.22)
            }
            if hasStrongAlternateRoot {
                bestConfidence = min(bestConfidence, 0.79)
            }
        }

        guard let primary = candidates.first else { return nil }
        let blendedConfidence = min(primary.confidence, bestConfidence)
        let finalConfidence: Double
        if blendedConfidence < 0.50 && primary.confidence >= 0.78 {
            finalConfidence = 0.62
        } else {
            finalConfidence = blendedConfidence
        }
        return ChordDetectionResult(
            name: primary.name,
            rootName: primary.rootName,
            confidence: finalConfidence,
            observedNoteNames: observedSet.sorted().map { noteNames[$0] },
            bassNoteName: bassPitchClass.map { noteNames[$0] },
            candidates: candidates
        )
    }

    private func detectBassPitchClass(noteBinWeights: [Double], observedSet: Set<Int>) -> Int? {
        guard let maxWeight = noteBinWeights.max(), maxWeight > 0.0008 else { return nil }
        let threshold = max(0.001, maxWeight * 0.14)
        let minimumMIDI = 35
        let maximumMIDI = 74

        struct BassCandidate {
            let midi: Int
            let pitchClass: Int
            let score: Double
        }

        var candidates: [BassCandidate] = []
        for (index, weight) in noteBinWeights.enumerated() {
            guard weight >= threshold else { continue }
            let midi = baseMIDINote + index
            guard midi >= minimumMIDI, midi <= maximumMIDI else { continue }

            let pitchClass = ((midi % 12) + 12) % 12
            guard observedSet.contains(pitchClass) else { continue }

            let octaveBias = 1.0 + (Double(maximumMIDI - midi) / 78.0)
            candidates.append(
                BassCandidate(
                    midi: midi,
                    pitchClass: pitchClass,
                    score: weight * octaveBias
                )
            )
        }

        guard !candidates.isEmpty else { return nil }
        let lowestMIDI = candidates.map(\.midi).min() ?? minimumMIDI
        let nearLowest = candidates.filter { $0.midi <= (lowestMIDI + 4) }
        return nearLowest.max(by: { $0.score < $1.score })?.pitchClass
    }

    private func chordLabel(root: Int, suffix: String) -> String {
        noteNames[root] + suffix
    }
}
