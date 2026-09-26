import SwiftUI

struct ChordFinderView: View {
    @Binding var isSessionActive: Bool

    @State private var model: ChordFinderViewModel

    // The tuner session is only needed to build the chord finder's own model,
    // so it isn't stored.
    init(session: TunerSession, isSessionActive: Binding<Bool>) {
        self._isSessionActive = isSessionActive
        self._model = State(initialValue: ChordFinderViewModel(audioSource: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chord Finder")
                .font(.title3.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)

            Text("Tap Start, play one chord once, then wait.")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)

            HStack(spacing: 10) {
                Button(isSessionActive ? "Stop" : "Start", action: toggleSession)
                    .buttonStyle(.primary(tint: isSessionActive ? AppTheme.danger : AppTheme.accent))

                statusBadge
            }

            if model.phase == .capturing {
                Text("Captured: \(model.samples.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if model.phase == .ready {
                Text("Ready: play one chord now")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if model.phase == .analyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("WAIT - analyzing...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.top, 2)
            }

            ChordResultCard(result: model.lastResult)

            Text("Tip: For best accuracy, let the chord ring for a short moment and avoid changing chords while WAIT is visible.")
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary)

            switch model.modelStatus {
            case .loading:
                Text("Preparing chord model...")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textTertiary)
            case .unavailable:
                Text("ML model not found in bundle (nmp.mlpackage/mlmodelc). Running fallback detector.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.warning)
            case .ready:
                EmptyView()
            }
        }
        // Loading the CoreML model takes a noticeable moment; keep it off the main
        // actor so switching to this tab does not stall the UI.
        .task {
            model.onRequestSessionEnd = { isSessionActive = false }
            await model.prepareModel()
        }
        // Tying the loop to task(id:) means SwiftUI cancels it when the session ends
        // or the view goes away — no Task handle to hold, cancel and forget to clear.
        // Starting and stopping the model happens synchronously elsewhere: waiting
        // for this task to be cancelled would leave a window where a finished
        // analysis could still land.
        .task(id: isSessionActive) {
            guard isSessionActive else { return }
            await model.runListeningLoop()
        }
        // Catches the session ending from outside the button — the tab changing, or
        // the analysis finishing and asking to close the one-shot session.
        .onChange(of: isSessionActive) { _, isActive in
            if !isActive {
                model.stopListening()
            }
        }
        .onDisappear {
            model.stopListening()
            isSessionActive = false
        }
    }

    private var statusBadge: some View {
        let label: LocalizedStringKey
        let color: Color

        switch model.phase {
        case .idle:
            label = "Idle"
            color = AppTheme.textTertiary
        case .ready:
            label = "Ready"
            color = AppTheme.success
        case .capturing:
            label = "Listening"
            color = AppTheme.accent
        case .analyzing:
            label = "WAIT"
            color = AppTheme.warning
        }

        return Text(label)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceSecondary)
                    .overlay(
                        Capsule().stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1)
                    )
            )
    }

    private func toggleSession() {
        if isSessionActive {
            model.stopListening()
            isSessionActive = false
        } else {
            model.beginListening()
            isSessionActive = true
        }
    }
}
