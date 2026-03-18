import Foundation

struct RegressionCheck: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
}

struct RegressionSuiteResult {
    let suiteName: String
    let checks: [RegressionCheck]

    var passed: Bool {
        checks.allSatisfy(\.passed)
    }

    var summaryLine: String {
        let passCount = checks.filter(\.passed).count
        return "\(suiteName): \(passCount)/\(checks.count) passed"
    }
}

enum TunerRegressionSuite {
    // Mirrors codex-rules/TUNER_QUALITY_BAR.md so the same quality bar is executable.
    private static let lockSuccessRateMin = 0.90
    private static let averageLockSecondsMax = 12.0
    private static let falseLockRateMax = 0.02
    private static let p95JumpMaxCentsPerFrame: Float = 12.0
    private static let signalDropRateMax = 0.08

    static func runAutoQualityBar(
        instrument: Instrument = InstrumentCatalog.guitar6,
        timeoutSeconds: Double = 15.0,
        frameRate: Double = 60.0
    ) -> RegressionSuiteResult {
        let report = TunerDiagnostics.runAutoValidationSuite(
            instrument: instrument,
            timeoutSeconds: timeoutSeconds,
            frameRate: frameRate
        )
        let falseLockRate = Double(report.falseLockCount) / Double(max(1, report.trialCount))

        let checks = [
            RegressionCheck(
                name: "Auto lock success rate",
                passed: report.lockSuccessRate >= lockSuccessRateMin,
                detail: String(format: "expected >= %.0f%%, got %.1f%%", lockSuccessRateMin * 100.0, report.lockSuccessRate * 100.0)
            ),
            RegressionCheck(
                name: "Auto average lock time",
                passed: report.averageLockSeconds <= averageLockSecondsMax,
                detail: String(format: "expected <= %.1fs, got %.2fs", averageLockSecondsMax, report.averageLockSeconds)
            ),
            RegressionCheck(
                name: "Auto false lock rate",
                passed: falseLockRate <= falseLockRateMax,
                detail: String(format: "expected <= %.1f%%, got %.1f%%", falseLockRateMax * 100.0, falseLockRate * 100.0)
            ),
            RegressionCheck(
                name: "Auto meter stability p95 jump",
                passed: report.p95JumpCentsPerFrame <= p95JumpMaxCentsPerFrame,
                detail: String(format: "expected <= %.1fc/frame, got %.1fc/frame", p95JumpMaxCentsPerFrame, report.p95JumpCentsPerFrame)
            ),
            RegressionCheck(
                name: "Auto signal drop rate",
                passed: report.signalDropRate <= signalDropRateMax,
                detail: String(format: "expected <= %.1f%%, got %.1f%%", signalDropRateMax * 100.0, report.signalDropRate * 100.0)
            )
        ]

        return RegressionSuiteResult(suiteName: "AutoQualityBar", checks: checks)
    }

    static func runManualStabilitySuite(
        instrument: Instrument = InstrumentCatalog.guitar6,
        duration: Double = 10.0,
        frameRate: Double = 60.0
    ) -> RegressionSuiteResult {
        let notes = instrument.defaultTuning.notes
        guard let low = notes.first, let high = notes.last else {
            return RegressionSuiteResult(
                suiteName: "ManualStability",
                checks: [
                    RegressionCheck(
                        name: "Manual setup",
                        passed: false,
                        detail: "Instrument has no tunable note range"
                    )
                ]
            )
        }

        let lowStress = TunerDiagnostics.runManualJitterScenario(
            target: low,
            duration: duration,
            frameRate: frameRate,
            profile: .harmonicStress
        )
        let highStress = TunerDiagnostics.runManualJitterScenario(
            target: high,
            duration: duration,
            frameRate: frameRate,
            profile: .harmonicStress
        )

        let worstP95 = max(lowStress.p95JumpCentsPerFrame, highStress.p95JumpCentsPerFrame)
        let worstDropCount = max(lowStress.signalDropCount, highStress.signalDropCount)
        let allowedSignalDrops = Int((duration * frameRate) * 0.12)

        let checks = [
            RegressionCheck(
                name: "Manual edge-string p95 jump",
                passed: worstP95 <= 14.0,
                detail: String(format: "expected <= 14.0c/frame, got %.1fc/frame", worstP95)
            ),
            RegressionCheck(
                name: "Manual edge-string signal drops",
                passed: worstDropCount <= allowedSignalDrops,
                detail: "expected <= \(allowedSignalDrops) drops, got \(worstDropCount)"
            )
        ]

        return RegressionSuiteResult(suiteName: "ManualStability", checks: checks)
    }

    static func runTuningPresetIntegritySuite(
        instrument: Instrument = InstrumentCatalog.guitar6
    ) -> RegressionSuiteResult {
        let groups = InstrumentCatalog.tuningGroups(for: instrument)
        let allTunings = groups.flatMap(\.tunings)
        let tuningNames = allTunings.map(\.name)

        let expectedCommon = [
            "E Standard", "Eb Standard", "D Standard", "C# Standard", "C Standard",
            "Drop D", "Drop C#", "Drop C",
            "B Standard", "Drop B", "Drop A"
        ]

        let containsCommon = expectedCommon.allSatisfy { tuningNames.contains($0) }
        let allSixStrings = allTunings.allSatisfy { $0.notes.count == 6 }
        let ascendingFrequencies = allTunings.allSatisfy { tuning in
            zip(tuning.notes, tuning.notes.dropFirst()).allSatisfy { lhs, rhs in lhs.frequency < rhs.frequency }
        }
        let uniqueNames = Set(tuningNames).count == tuningNames.count

        let checks = [
            RegressionCheck(
                name: "Preset includes required common tunings",
                passed: containsCommon,
                detail: "required=\(expectedCommon.count), available=\(tuningNames.count)"
            ),
            RegressionCheck(
                name: "All presets are 6-string definitions",
                passed: allSixStrings,
                detail: allSixStrings ? "all presets have 6 notes" : "one or more presets has invalid string count"
            ),
            RegressionCheck(
                name: "Preset frequencies are strictly ascending",
                passed: ascendingFrequencies,
                detail: ascendingFrequencies ? "all presets sorted low-to-high" : "one or more presets has non-ascending frequencies"
            ),
            RegressionCheck(
                name: "Preset names are unique",
                passed: uniqueNames,
                detail: uniqueNames ? "all names unique" : "duplicate preset names detected"
            )
        ]

        return RegressionSuiteResult(suiteName: "TuningPresetIntegrity", checks: checks)
    }

    static func runAll() -> [RegressionSuiteResult] {
        [
            runAutoQualityBar(),
            runManualStabilitySuite(),
            runTuningPresetIntegritySuite()
        ]
    }

    static func formattedReport() -> String {
        let suites = runAll()
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        lines.append("DeepTune Regression Suite @ \(formatter.string(from: Date()))")

        for suite in suites {
            lines.append(suite.summaryLine)
            for check in suite.checks {
                lines.append("- [\(check.passed ? "PASS" : "FAIL")] \(check.name) -> \(check.detail)")
            }
        }

        let passedSuites = suites.filter(\.passed).count
        lines.append("Overall: \(passedSuites)/\(suites.count) suites passed")
        return lines.joined(separator: "\n")
    }
}
