import Foundation
import CoreML

struct ChordDetectionResult {
    let name: String
    let confidence: Double
    let observedNoteNames: [String]
}

final class BasicPitchChordAnalyzer {
    static let shared = BasicPitchChordAnalyzer()

    private let audioSampleRate: Double = 22_050.0
    private let fftHop = 256
    private let audioWindowLengthSeconds = 2
    private let expectedAudioSampleCount = 43_844
    private let noteBins = 88
    private let baseMIDINote = 21 // A0

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private let templates: [(suffix: String, intervals: [Int])] = [
        ("", [0, 4, 7]),
        ("m", [0, 3, 7]),
        ("5", [0, 7]),
        ("sus2", [0, 2, 7]),
        ("sus4", [0, 5, 7]),
        ("dim", [0, 3, 6]),
        ("aug", [0, 4, 8]),
        ("7", [0, 4, 7, 10]),
        ("maj7", [0, 4, 7, 11]),
        ("m7", [0, 3, 7, 10])
    ]

    private lazy var model: MLModel? = {
        Self.loadModel()
    }()

    var isModelAvailable: Bool {
        model != nil
    }

    private init() {}

    func analyze(audioWindow: AudioSampleWindow) -> ChordDetectionResult? {
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

            guard let pitchClassWeights = extractPitchClassWeights(from: output) else {
                return nil
            }

            return decodeChord(fromPitchClassWeights: pitchClassWeights)
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
        let rank = shape.count
        let timeAxis = rank - 1
        let count = min(samples.count, shape[timeAxis])

        for i in 0..<count {
            let offset = i * strides[timeAxis]
            setMultiArrayValue(array, offset: offset, value: Double(samples[i]))
        }
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

    private func extractPitchClassWeights(from output: MLFeatureProvider) -> [Double]? {
        var bestWeights: [Double]?
        var bestEnergy = 0.0

        for featureName in output.featureNames {
            guard let featureValue = output.featureValue(for: featureName),
                  featureValue.type == .multiArray,
                  let array = featureValue.multiArrayValue else {
                continue
            }

            guard let noteWeights = aggregateNoteWeights(from: array) else { continue }
            let totalEnergy = noteWeights.reduce(0, +)
            guard totalEnergy > bestEnergy else { continue }

            bestEnergy = totalEnergy
            bestWeights = noteWeights
        }

        guard let bestWeights, bestWeights.reduce(0, +) > 0.01 else {
            return nil
        }

        var pitchClassWeights = [Double](repeating: 0.0, count: 12)
        for (noteBin, weight) in bestWeights.enumerated() {
            let midi = baseMIDINote + noteBin
            let pitchClass = ((midi % 12) + 12) % 12
            pitchClassWeights[pitchClass] += weight
        }

        return pitchClassWeights
    }

    private func aggregateNoteWeights(from array: MLMultiArray) -> [Double]? {
        let shape = array.shape.map { $0.intValue }
        guard let noteAxis = shape.firstIndex(of: noteBins) else { return nil }

        let strides = array.strides.map { $0.intValue }
        var indices = [Int](repeating: 0, count: shape.count)
        var noteWeights = [Double](repeating: 0.0, count: noteBins)

        func traverse(_ axis: Int) {
            if axis == shape.count {
                let noteBin = indices[noteAxis]
                var offset = 0
                for (index, stride) in zip(indices, strides) {
                    offset += index * stride
                }

                let value = readMultiArrayValue(array, offset: offset)
                if value > 0 {
                    noteWeights[noteBin] += value
                }
                return
            }

            for index in 0..<shape[axis] {
                indices[axis] = index
                traverse(axis + 1)
            }
        }

        traverse(0)
        return noteWeights
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

    private func decodeChord(fromPitchClassWeights pitchClassWeights: [Double]) -> ChordDetectionResult? {
        let maxWeight = pitchClassWeights.max() ?? 0
        guard maxWeight > 0.001 else { return nil }

        let threshold = max(maxWeight * 0.18, 0.001)
        let observedSet = Set(
            pitchClassWeights.enumerated()
                .filter { $0.element >= threshold }
                .map { $0.offset }
        )
        guard observedSet.count >= 2 else { return nil }

        struct Match {
            let root: Int
            let suffix: String
            let score: Double
            let matchedWeight: Double
            let expected: Set<Int>
            let extraWeight: Double
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

                let score = (matchedWeight * 2.0) - (Double(missingCount) * 3.0) - (extraWeight * 1.25)
                matches.append(
                    Match(
                        root: root,
                        suffix: template.suffix,
                        score: score,
                        matchedWeight: matchedWeight,
                        expected: expected,
                        extraWeight: extraWeight
                    )
                )
            }
        }

        let ranked = matches.sorted { lhs, rhs in lhs.score > rhs.score }
        guard let best = ranked.first else { return nil }
        guard best.score > 0.9 else { return nil }

        let matchedCoverage = best.matchedWeight / max(1e-6, totalWeight)
        let expectedCoverage = Double(best.expected.intersection(observedSet).count) / Double(best.expected.count)
        guard matchedCoverage >= 0.58, expectedCoverage >= 0.66 else { return nil }

        var ambiguityMargin = 1.0
        if ranked.count >= 2 {
            let second = ranked[1]
            ambiguityMargin = max(0.0, min(1.0, (best.score - second.score) / max(1.0, abs(best.score))))
            guard ambiguityMargin >= 0.07 else { return nil }
        }

        let confidence = max(
            0.12,
            min(
                0.88,
                0.20
                    + (matchedCoverage * 0.38)
                    + (expectedCoverage * 0.30)
                    + (ambiguityMargin * 0.20)
                    - ((best.extraWeight / max(1e-6, totalWeight)) * 0.22)
            )
        )
        guard confidence >= 0.26 else { return nil }

        return ChordDetectionResult(
            name: noteNames[best.root] + best.suffix,
            confidence: confidence,
            observedNoteNames: observedSet.sorted().map { noteNames[$0] }
        )
    }
}
