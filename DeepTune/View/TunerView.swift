import SwiftUI

struct TunerView: View {
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = TunerViewModel()
    @StateObject private var permissionManager = PermissionManager()

    @State private var showSettings = false
    @State private var showTuningPicker = false
    @State private var showPermissionAlert = false
    @State private var selectedMode: TunerMode = .auto

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            TabView(selection: $selectedMode) {
                autoModeView
                    .tabItem {
                        Label("Auto", systemImage: "guitars")
                    }
                    .tag(TunerMode.auto)
                    .onAppear {
                        if viewModel.targetNote == nil {
                            viewModel.setTargetNote(viewModel.currentTuning.notes.first)
                        }
                    }

                manualModeView
                    .tabItem {
                        Label("Manual", systemImage: "waveform.path")
                    }
                    .tag(TunerMode.manual)
            }
        }
        .tint(AppTheme.accent)
        .onAppear {
            viewModel.setActiveMode(selectedMode)
            permissionManager.requestMicrophonePermission { granted in
                if granted {
                    viewModel.start()
                }
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            viewModel.setActiveMode(newMode)
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $showTuningPicker) {
            TuningPickerView(viewModel: viewModel)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Settings", role: .none) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("DeepTune needs microphone access to detect pitch. Please enable it in Settings.")
        }
    }

    private var autoModeView: some View {
        GeometryReader { _ in
            ZStack {
                AppTheme.backgroundTop
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    headerView
                        .frame(height: 88)

                    VStack(spacing: 6) {
                        AutoStrobeArea(
                            centsDistance: viewModel.autoCentsDistance,
                            targetNote: viewModel.targetNote,
                            isTuningSuccessful: viewModel.isTuningSuccessful,
                            isSignalDetected: viewModel.isTargetSignalDetected,
                            hasPitchReference: viewModel.hasPitchReference
                        )

                    HStack {
                        Text(String(format: "%.1f cents", viewModel.autoCentsDistance))
                            .font(.headline.weight(.semibold))
                            .foregroundColor(autoFeedbackColor)

                        Spacer()

                        Text("Progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.top, 2)

                    autoProgressBar
                        .opacity(viewModel.isTargetSignalDetected || viewModel.tuneProgressRatio > 0 ? 1.0 : 0.45)

                    HStack {
                        Spacer()
                        floatingAutoProgressControl
                    }
                    .padding(.top, 2)

                    headstockView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
    }

    private var autoFeedbackColor: Color {
        AppTheme.autoStrobeRampColor(
            centsDistance: viewModel.autoCentsDistance,
            isSignalDetected: viewModel.isTargetSignalDetected,
            visualRangeCents: 80.0
        )
    }

    private var autoProgressBar: some View {
        GeometryReader { proxy in
            let ratio = CGFloat(max(0.0, min(1.0, viewModel.tuneProgressRatio)))
            let fillWidth = max(CGFloat(6.0), proxy.size.width * ratio)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.stroke.opacity(0.35))
                Capsule()
                    .fill(autoFeedbackColor)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 9)
    }

    private var manualModeView: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    headerView
                        .frame(height: 88)

                    ManualStrobeArea(
                        centsDistance: viewModel.manualCentsDistance,
                        detectedNote: viewModel.detectedNote,
                        isSignalDetected: viewModel.isSignalDetected
                    )
                    .padding(16)
                    .appCard()

                    manualInfoPanel
                        .padding(16)
                        .appCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 104)
            }
        }
    }

    private var floatingAutoProgressControl: some View {
        HStack(spacing: 8) {
            Text("Auto")
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)
            Toggle("", isOn: $viewModel.isAutoProgressEnabled)
                .labelsHidden()
                .tint(AppTheme.accent)
                .scaleEffect(0.84)
            Text(viewModel.isAutoProgressEnabled ? "On" : "Off")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.isAutoProgressEnabled ? AppTheme.success : AppTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(AppTheme.surfaceSecondary.opacity(0.85))
                .overlay(Capsule().stroke(AppTheme.stroke.opacity(0.8), lineWidth: 1))
        )
    }

    private var manualInfoPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(viewModel.detectedNote?.name ?? "--")
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundColor(viewModel.isSignalDetected ? AppTheme.textPrimary : AppTheme.textTertiary)

                Text(viewModel.detectedNote.map { "\($0.octave)" } ?? "")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Text(
                viewModel.detectedNote.map { String(format: "Nearest %.2f Hz", $0.nearestFrequency) }
                    ?? "Play a note to detect frequency"
            )
            .font(.subheadline.weight(.medium))
            .foregroundColor(AppTheme.textSecondary)

            HStack(spacing: 10) {
                manualRangeCard(
                    title: "Lowest",
                    value: viewModel.manualLowestFrequency.map { String(format: "%.2f Hz", $0) } ?? "--"
                )
                manualRangeCard(
                    title: "Highest",
                    value: viewModel.manualHighestFrequency.map { String(format: "%.2f Hz", $0) } ?? "--"
                )
            }

            Text("Manual mode follows the note you play instead of the selected tuning string.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 8)
        }
    }

    private func manualRangeCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppTheme.textTertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var headerView: some View {
        ZStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    compactSelector(
                        icon: instrumentIconName(for: viewModel.currentInstrument.type),
                        title: viewModel.currentInstrument.name,
                        isInteractive: false
                    )

                    Button(action: { showTuningPicker.toggle() }) {
                        compactSelector(
                            icon: "dial.medium.fill",
                            title: viewModel.currentTuning.name,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        if !permissionManager.isMicrophoneGranted {
                            showPermissionAlert = true
                        }
                    }) {
                        Image(systemName: permissionManager.isMicrophoneGranted ? "mic.fill" : "mic.slash.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(permissionManager.isMicrophoneGranted ? AppTheme.success : AppTheme.danger)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(AppTheme.surfaceSecondary)
                                    .overlay(
                                        Circle()
                                            .stroke(AppTheme.stroke.opacity(colorScheme == .dark ? 0.95 : 0.85), lineWidth: 1)
                                    )
                                    .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(0.26) : Color.black.opacity(0.12)), radius: 5, x: 0, y: 2)
                            )
                    }

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(AppTheme.surfaceSecondary)
                                    .overlay(
                                        Circle()
                                            .stroke(AppTheme.stroke.opacity(colorScheme == .dark ? 0.95 : 0.85), lineWidth: 1)
                                    )
                                    .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(0.26) : Color.black.opacity(0.12)), radius: 5, x: 0, y: 2)
                            )
                    }
                }
            }

            VStack(spacing: 1) {
                Text("DeepTune")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, 120)
        }
    }

    private func compactSelector(icon: String, title: String, isInteractive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppTheme.accentSoft))

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isInteractive {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke.opacity(colorScheme == .dark ? 0.95 : 0.85), lineWidth: 1)
                )
                .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(0.20) : Color.black.opacity(0.10)), radius: 4, x: 0, y: 2)
        )
        .frame(width: 134, alignment: .leading)
    }

    // Keeps the headstock zone clear and flexible for future image overlays.
    private var headstockView: some View {
        GeometryReader { proxy in
            let columnSpacing = max(70, min(104, proxy.size.width * 0.34))
            let pegSpacing = max(24, min(44, proxy.size.height * 0.22))

            ZStack(alignment: .bottom) {
                pegLayout(columnSpacing: columnSpacing, pegSpacing: pegSpacing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(8, proxy.size.height * 0.06))

                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Future guitar headstock artwork area")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func pegLayout(columnSpacing: CGFloat, pegSpacing: CGFloat) -> some View {
        let notes = viewModel.currentTuning.notes

        if notes.count == 6 {
            HStack(spacing: columnSpacing) {
                VStack(spacing: pegSpacing) {
                    peg(for: notes[0])
                    peg(for: notes[1])
                    peg(for: notes[2])
                }

                VStack(spacing: pegSpacing) {
                    peg(for: notes[3])
                    peg(for: notes[4])
                    peg(for: notes[5])
                }
            }
        } else if notes.count == 7 {
            HStack(spacing: columnSpacing) {
                VStack(spacing: pegSpacing * 0.86) {
                    peg(for: notes[0])
                    peg(for: notes[1])
                    peg(for: notes[2])
                    peg(for: notes[3])
                }

                VStack(spacing: pegSpacing * 0.86) {
                    peg(for: notes[4])
                    peg(for: notes[5])
                    peg(for: notes[6])
                }
            }
        } else if notes.count == 4 {
            HStack(spacing: columnSpacing * 0.9) {
                VStack(spacing: pegSpacing * 1.2) {
                    peg(for: notes[0])
                    peg(for: notes[1])
                }

                VStack(spacing: pegSpacing * 1.2) {
                    peg(for: notes[2])
                    peg(for: notes[3])
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(notes) { note in
                    peg(for: note)
                }
            }
        }
    }

    private func instrumentIconName(for type: InstrumentType) -> String {
        switch type {
        case .guitar6, .guitar7, .guitar8:
            return "guitars.fill"
        case .bass:
            return "music.note.list"
        case .ukulele:
            return "music.quarternote.3"
        }
    }

    private func peg(for note: Note) -> some View {
        PegButton(
            note: note,
            isActive: viewModel.targetNote == note,
            isCompleted: viewModel.isNoteCompleted(note)
        )
        .onTapGesture {
            viewModel.setTargetNote(note)
        }
    }
}

struct PegButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var note: Note
    var isActive: Bool
    var isCompleted: Bool = false

    var body: some View {
        Text(note.name)
            .font(.headline.weight(.bold))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(isActive ? AppTheme.accent : AppTheme.surfaceElevated)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.stroke.opacity(isActive ? (colorScheme == .dark ? 0.40 : 0.40) : (colorScheme == .dark ? 0.85 : 0.85)), lineWidth: 1)
                    )
                    .shadow(color: (colorScheme == .dark ? AppTheme.accent.opacity(isActive ? 0.32 : 0.18) : Color.black.opacity(isActive ? 0.20 : 0.08)), radius: isActive ? 8 : 5, x: 0, y: 3)
            )
            .foregroundColor(isActive ? .white : AppTheme.textPrimary)
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isActive)
            .overlay(alignment: .topTrailing) {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.success)
                        .background(Circle().fill(AppTheme.surfacePrimary))
                        .offset(x: 4, y: -4)
                }
            }
    }
}

#Preview {
    TunerView()
}

#Preview("Dark") {
    TunerView()
        .preferredColorScheme(.dark)
}
