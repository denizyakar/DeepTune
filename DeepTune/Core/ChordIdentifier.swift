import Foundation

/// One chord the identifier considers plausible for the notes it was given.
struct ChordCandidate: Equatable {
    let name: String
    let rootName: String
    let confidence: Double
}

/// The identifier's verdict: a best guess plus the alternatives it ranked behind it.
struct ChordIdentification: Equatable {
    let name: String
    let rootName: String
    let confidence: Double
    let observedNoteNames: [String]
    let candidates: [ChordCandidate]
}

/// Template-matching chord identification over pitch-class weights.
///
/// This is the fallback used when the CoreML model is unavailable. It takes plain
/// pitch-class counts rather than anything from the audio or view layer, so its
/// decisions can be tested directly.
enum ChordIdentifier {
    static let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private struct Template {
        let suffix: String
        let intervals: [Int]
    }

    private static let templates: [Template] = [
        Template(suffix: "", intervals: [0, 4, 7]),
        Template(suffix: "m", intervals: [0, 3, 7]),
        Template(suffix: "5", intervals: [0, 7]),
        Template(suffix: "sus2", intervals: [0, 2, 7]),
        Template(suffix: "sus4", intervals: [0, 5, 7]),
        Template(suffix: "dim", intervals: [0, 3, 6]),
        Template(suffix: "aug", intervals: [0, 4, 8]),
        Template(suffix: "7", intervals: [0, 4, 7, 10]),
        Template(suffix: "maj7", intervals: [0, 4, 7, 11]),
        Template(suffix: "m7", intervals: [0, 3, 7, 10])
    ]

    private struct MatchScore {
        let root: Int
        let suffix: String
        let score: Double
        let expectedPitchClasses: Set<Int>
        let matchedWeight: Double
        let missingCount: Int
        let extraWeight: Double
    }

    /// - Parameter counts: how often each pitch class (0 = C ... 11 = B) was heard.
    /// - Returns: nil when the evidence is too thin or too ambiguous to name a chord.
    static func identify(pitchClassCounts counts: [Int: Int]) -> ChordIdentification? {
        guard !counts.isEmpty else { return nil }

        let observedSet = filteredObservedPitchClasses(from: counts)
        guard observedSet.count >= 2 else { return nil }

        let rankedMatches = rankedMatches(counts: counts, observedSet: observedSet)
        guard let best = rankedMatches.first else { return nil }
        guard best.score > 1.2 else { return nil }

        if best.expectedPitchClasses.count >= 3, observedSet.count < 3 {
            return nil
        }

        let totalWeight = Double(counts.values.reduce(0, +))
        let matchedCoverage = best.matchedWeight / max(1.0, totalWeight)
        let requiredCoverage = best.expectedPitchClasses.count == 2 ? 0.50 : 0.58
        guard matchedCoverage >= requiredCoverage else { return nil }

        let matchedPitchClassCount = Double(best.expectedPitchClasses.intersection(observedSet).count)
        let setCoverage = matchedPitchClassCount / Double(best.expectedPitchClasses.count)
        let requiredSetCoverage = best.expectedPitchClasses.count == 2 ? 0.50 : 0.66
        guard setCoverage >= requiredSetCoverage else { return nil }

        let ambiguityMargin: Double
        if rankedMatches.count >= 2 {
            let second = rankedMatches[1]
            ambiguityMargin = max(0.0, min(1.0, (best.score - second.score) / max(1.0, abs(best.score))))
            guard ambiguityMargin >= 0.08 else { return nil }
        } else {
            ambiguityMargin = 1.0
        }

        let extraPenalty = (best.extraWeight / max(1.0, totalWeight)) * 0.22
        let confidence = max(
            0.12,
            min(
                0.82,
                0.20 + (matchedCoverage * 0.34) + (setCoverage * 0.28) + (ambiguityMargin * 0.20) - extraPenalty
            )
        )
        guard confidence >= 0.26 else { return nil }

        let primaryName = pitchClassNames[best.root] + best.suffix
        let topMatches = Array(rankedMatches.prefix(5))
        let candidates: [ChordCandidate] = topMatches.map { match in
            let delta = max(0.0, best.score - match.score)
            let closeness = max(0.0, min(1.0, 1.0 - (delta / 6.0)))
            let candidateConfidence = max(
                0.08,
                min(
                    0.92,
                    0.12 + (closeness * 0.46) + (match.matchedWeight / max(1.0, totalWeight) * 0.26)
                )
            )
            return ChordCandidate(
                name: pitchClassNames[match.root] + match.suffix,
                rootName: pitchClassNames[match.root],
                confidence: candidateConfidence
            )
        }

        return ChordIdentification(
            name: primaryName,
            rootName: pitchClassNames[best.root],
            confidence: confidence,
            observedNoteNames: observedSet.sorted().map { pitchClassNames[$0] },
            candidates: candidates
        )
    }

    static func observedNoteNames(pitchClassCounts counts: [Int: Int]) -> [String] {
        let observedSet = filteredObservedPitchClasses(from: counts)
        return observedSet.sorted().map { pitchClassNames[$0] }
    }

    private static func filteredObservedPitchClasses(from counts: [Int: Int]) -> Set<Int> {
        guard let maxWeight = counts.values.max() else { return [] }
        let threshold = max(1, Int(Double(maxWeight) * 0.16))
        return Set(counts.filter { $0.value >= threshold }.map { $0.key })
    }

    private static func rankedMatches(counts: [Int: Int], observedSet: Set<Int>) -> [MatchScore] {
        var matches: [MatchScore] = []
        for root in 0..<12 {
            for template in templates {
                let expected = Set(template.intervals.map { (root + $0) % 12 })
                let matchedWeight = expected.reduce(0.0) { partial, pitchClass in
                    partial + Double(counts[pitchClass] ?? 0)
                }
                let missingCount = expected.filter { counts[$0] == nil }.count
                let extraWeight = observedSet.subtracting(expected).reduce(0.0) { partial, pitchClass in
                    partial + Double(counts[pitchClass] ?? 0)
                }

                let score = (matchedWeight * 2.0) - (Double(missingCount) * 3.0) - (extraWeight * 1.35)
                matches.append(
                    MatchScore(
                        root: root,
                        suffix: template.suffix,
                        score: score,
                        expectedPitchClasses: expected,
                        matchedWeight: matchedWeight,
                        missingCount: missingCount,
                        extraWeight: extraWeight
                    )
                )
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.missingCount < rhs.missingCount
            }
            return lhs.score > rhs.score
        }
    }
}
