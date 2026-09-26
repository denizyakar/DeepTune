import SwiftUI

// Each demo drives a real tuner component with scripted values. Nothing here
// restyles those components, so a theme or component change shows up in
// onboarding without touching it.

/// Timeline shared by the demos: runs only while its page is on screen and
/// holds a still frame when Reduce Motion is on.
private struct DemoTimeline<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    @ViewBuilder let content: (TimeInterval) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { context in
            content(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
    }
}

// MARK: - Instruments

struct InstrumentsDemo: View {
    let isActive: Bool

    private let instruments = InstrumentCatalog.selectableInstruments
    private let secondsPerInstrument = 2.4

    var body: some View {
        DemoTimeline(isActive: isActive) { time in
            let instrument = instruments[Int(time / secondsPerInstrument) % instruments.count]

            VStack(spacing: 14) {
                CompactSelector(icon: instrument.type.iconName, title: instrument.name, isInteractive: true)

                Image(instrument.type.headstockImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 230)
                    .id(instrument.type)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                HStack(spacing: 8) {
                    ForEach(instrument.defaultTuning.notes) { note in
                        Text(note.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(AppTheme.accentSoft))
                    }
                }
                .id(instrument.type)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.45), value: instrument.type)
            .frame(maxWidth: .infinity)
            .padding(20)
            .appCard()
        }
    }
}

// MARK: - Tunings

struct TuningsDemo: View {
    let isActive: Bool

    private let groups = InstrumentCatalog.tuningGroups(for: InstrumentCatalog.guitar6).prefix(3)
    private let secondsPerHighlight = 1.1

    var body: some View {
        DemoTimeline(isActive: isActive) { time in
            let tunings = groups.flatMap(\.tunings)
            let highlighted = tunings[Int(time / secondsPerHighlight) % tunings.count]

            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)

                        FlowLayout(spacing: 6) {
                            ForEach(group.tunings) { tuning in
                                TuningChip(name: tuning.name, isHighlighted: tuning == highlighted)
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: highlighted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .appCard()
        }
    }
}

private struct TuningChip: View {
    let name: String
    let isHighlighted: Bool

    var body: some View {
        Text(name)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isHighlighted ? Color.white : AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isHighlighted ? AppTheme.accent : AppTheme.surfaceSecondary)
                    .overlay(Capsule().stroke(AppTheme.stroke.opacity(0.7), lineWidth: 1))
            )
    }
}

// MARK: - Auto and Manual

struct TuningModesDemo: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 12) {
            AutoModeDemo(isActive: isActive)
            ManualModeDemo(isActive: isActive)
        }
    }
}

private struct AutoModeDemo: View {
    let isActive: Bool

    private let notes = InstrumentCatalog.guitar6.defaultTuning.notes
    // One string: approach from flat, settle, hold in tune, then move on.
    private let secondsPerString = 3.2
    private let settleSeconds = 2.0

    var body: some View {
        DemoTimeline(isActive: isActive) { time in
            let local = time.truncatingRemainder(dividingBy: secondsPerString)
            let note = notes[Int(time / secondsPerString) % notes.count]
            let isInTune = local >= settleSeconds
            let cents = isInTune
                ? Float(0.6 * sin(local * 6))
                : Float(-38 * exp(-2.0 * local) * cos(4.5 * local))

            VStack(alignment: .leading, spacing: 10) {
                DemoCaption(title: "Auto", detail: "Moves to the next string once it’s in tune")

                AutoStrobeArea(
                    centsDistance: cents,
                    targetNote: note,
                    isTuningSuccessful: isInTune,
                    isSignalDetected: true,
                    hasPitchReference: true
                )
            }
            .padding(16)
            .appCard()
        }
    }
}

private struct ManualModeDemo: View {
    let isActive: Bool

    // A slow walk across the open strings, drifting a little around each note.
    private let midiNumbers = [40, 45, 50, 55, 59, 64]
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let secondsPerNote = 1.8

    var body: some View {
        DemoTimeline(isActive: isActive) { time in
            let midi = midiNumbers[Int(time / secondsPerNote) % midiNumbers.count]
            let cents = Float(14 * sin(time * 1.9))
            let note = DetectedNote(
                name: noteNames[midi % 12],
                octave: midi / 12 - 1,
                midiNumber: midi,
                nearestFrequency: Float(PitchCalibration.standard.frequency(ofMIDI: midi)),
                centsFromEqualTempered: cents
            )

            VStack(alignment: .leading, spacing: 10) {
                DemoCaption(title: "Manual", detail: "Follows any note you play")

                ManualStrobeArea(centsDistance: cents, detectedNote: note, isSignalDetected: true)
            }
            .padding(16)
            .appCard()
        }
    }
}

private struct DemoCaption: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
            Text(detail)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

// MARK: - Chord Finder

struct ChordFinderDemo: View {
    let isActive: Bool

    private let secondsPerChord = 2.8

    private static let samples: [ChordFinderViewModel.ChordMatch] = [
        sample("G", root: "G", confidence: 0.93, notes: ["G", "B", "D"], runnersUp: [("Em7", "E", 0.41), ("G6", "G", 0.33)]),
        sample("Am7", root: "A", confidence: 0.86, notes: ["A", "C", "E", "G"], runnersUp: [("C6", "C", 0.82), ("Am", "A", 0.52)]),
        sample("Dsus4", root: "D", confidence: 0.88, notes: ["D", "G", "A"], runnersUp: [("Gsus2", "G", 0.47), ("D", "D", 0.35)]),
    ]

    var body: some View {
        DemoTimeline(isActive: isActive) { time in
            let index = Int(time / secondsPerChord) % Self.samples.count

            // The animation sits on the container: a view whose identity changes
            // can't animate its own transition.
            ZStack {
                ChordResultCard(result: Self.samples[index])
                    .id(index)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.4), value: index)
            .padding(16)
            .appCard()
        }
    }

    private static func sample(
        _ name: String,
        root: String,
        confidence: Double,
        notes: [String],
        runnersUp: [(name: String, root: String, confidence: Double)]
    ) -> ChordFinderViewModel.ChordMatch {
        let top = ChordFinderViewModel.ChordSuggestion(name: name, rootName: root, confidence: confidence)
        let others = runnersUp.map {
            ChordFinderViewModel.ChordSuggestion(name: $0.name, rootName: $0.root, confidence: $0.confidence)
        }
        return ChordFinderViewModel.ChordMatch(
            name: name,
            rootName: root,
            confidence: confidence,
            observedNoteNames: notes,
            bassNoteName: root,
            candidates: [top] + others
        )
    }
}
