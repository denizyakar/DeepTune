import SwiftUI

private enum TunerTab: Hashable {
    case auto
    case manual
    case chord
}

struct TunerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: TunerViewModel
    @StateObject private var permissionManager: PermissionManager

    @State private var showSettings = false
    @State private var showInstrumentPicker = false
    @State private var showTuningPicker = false
    @State private var showPermissionAlert = false
    @State private var selectedTab: TunerTab = .auto
    @State private var isChordFinderSessionActive = false

    init(initialInstrument: Instrument = InstrumentCatalog.guitar6) {
        _viewModel = StateObject(wrappedValue: TunerViewModel(instrument: initialInstrument))
        _permissionManager = StateObject(wrappedValue: PermissionManager())
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                autoModeView
                    .tabItem {
                        Label("Auto", systemImage: "guitars")
                    }
                    .tag(TunerTab.auto)
                    .onAppear {
                        if viewModel.targetNote == nil {
                            viewModel.setTargetNote(viewModel.currentTuning.notes.first)
                        }
                    }

                manualModeView
                    .tabItem {
                        Label("Manual", systemImage: "waveform.path")
                    }
                    .tag(TunerTab.manual)

                chordModeView
                    .tabItem {
                        Label("Chord", systemImage: "music.note")
                    }
                    .tag(TunerTab.chord)
            }
        }
        .tint(AppTheme.accent)
        .onAppear {
            applyAudioTrackingMode(for: selectedTab)
            ensureMicrophonePermission()
            synchronizeAudioState()
        }
        .onChange(of: selectedTab) { _, newTab in
            applyAudioTrackingMode(for: newTab)
            if newTab != .chord {
                isChordFinderSessionActive = false
            }
            synchronizeAudioState()
        }
        .onChange(of: permissionManager.isMicrophoneGranted) { _, _ in
            synchronizeAudioState()
        }
        .onChange(of: scenePhase) { _, _ in
            synchronizeAudioState()
        }
        .onChange(of: isChordFinderSessionActive) { _, _ in
            synchronizeAudioState()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $showInstrumentPicker) {
            InstrumentPickerView(viewModel: viewModel)
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

    private var shouldRunAudioEngine: Bool {
        guard scenePhase == .active, permissionManager.isMicrophoneGranted else { return false }

        switch selectedTab {
        case .auto, .manual:
            return true
        case .chord:
            return isChordFinderSessionActive
        }
    }

    private func synchronizeAudioState() {
        if shouldRunAudioEngine {
            viewModel.start()
        } else {
            viewModel.stop()
        }
    }

    private func ensureMicrophonePermission() {
        guard !permissionManager.isMicrophoneGranted else { return }
        permissionManager.requestMicrophonePermission { _ in
            synchronizeAudioState()
        }
    }

    private func applyAudioTrackingMode(for tab: TunerTab) {
        switch tab {
        case .auto:
            viewModel.setActiveMode(.auto)
        case .manual, .chord:
            viewModel.setActiveMode(.manual)
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

    private var chordModeView: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    headerView
                        .frame(height: 88)

                    ChordFinderView(
                        viewModel: viewModel,
                        isSessionActive: $isChordFinderSessionActive
                    )
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
                    Button(action: { showInstrumentPicker.toggle() }) {
                        compactSelector(
                            icon: instrumentIconName(for: viewModel.currentInstrument.type),
                            title: viewModel.currentInstrument.name,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(.plain)

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

    private struct PegAnchor: Identifiable {
        let noteIndex: Int
        let x: CGFloat
        let y: CGFloat

        var id: Int { noteIndex }
    }

    // Keeps the headstock zone clear and flexible for future image overlays.
    private var headstockView: some View {
        GeometryReader { proxy in
            let headstockCanvasSize = CGSize(
                width: proxy.size.width * 1.06,
                height: proxy.size.height * 1.56
            )

            ZStack {
                ZStack(alignment: .topLeading) {
                    Image(headstockAssetName(for: viewModel.currentInstrument.type))
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: headstockCanvasSize.width,
                            height: headstockCanvasSize.height,
                            alignment: .bottom
                        )
                        .clipped()
                        .allowsHitTesting(false)

                    pegLayout(in: headstockCanvasSize)
                        .frame(
                            width: headstockCanvasSize.width,
                            height: headstockCanvasSize.height,
                            alignment: .topLeading
                        )
                }
                .frame(
                    width: headstockCanvasSize.width,
                    height: headstockCanvasSize.height,
                    alignment: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
        }
    }

    @ViewBuilder
    private func pegLayout(in canvasSize: CGSize) -> some View {
        let notes = viewModel.currentTuning.notes
        let anchors = pegAnchors(
            for: viewModel.currentInstrument.type,
            noteCount: notes.count
        )

        if anchors.isEmpty {
            HStack(spacing: 10) {
                ForEach(notes) { note in
                    peg(for: note)
                }
            }
        } else {
            ZStack {
                ForEach(anchors) { anchor in
                    if anchor.noteIndex < notes.count {
                        peg(for: notes[anchor.noteIndex])
                            .position(
                                x: canvasSize.width * anchor.x,
                                y: canvasSize.height * anchor.y
                            )
                    }
                }
            }
        }
    }

    private func headstockAssetName(for type: InstrumentType) -> String {
        switch type {
        case .guitar6:
            return "Guitar6Headstock"
        case .guitar7, .guitar8:
            return "Guitar7Headstock"
        case .bass:
            return "Bass4Headstock"
        case .ukulele:
            return "Ukulele4Headstock"
        }
    }

    private func pegAnchors(for type: InstrumentType, noteCount: Int) -> [PegAnchor] {
        switch type {
        case .guitar6:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.12, y: 0.388),
                PegAnchor(noteIndex: 2, x: 0.165, y: 0.31),
                PegAnchor(noteIndex: 3, x: 0.21, y: 0.235),
                PegAnchor(noteIndex: 4, x: 0.255, y: 0.16),
                PegAnchor(noteIndex: 5, x: 0.30, y: 0.085)
            ]
        case .guitar7, .guitar8:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.12, y: 0.388),
                PegAnchor(noteIndex: 2, x: 0.165, y: 0.31),
                PegAnchor(noteIndex: 3, x: 0.21, y: 0.235),
                PegAnchor(noteIndex: 4, x: 0.26, y: 0.23),
                PegAnchor(noteIndex: 5, x: 0.28, y: 0.15),
                PegAnchor(noteIndex: 6, x: 0.30, y: 0.08),
                PegAnchor(noteIndex: 7, x: 0.32, y: 0.05)
            ].prefix(noteCount).map { $0 }
        case .bass:
            return [
                PegAnchor(noteIndex: 0, x: 0.08, y: 0.465),
                PegAnchor(noteIndex: 1, x: 0.135, y: 0.34),
                PegAnchor(noteIndex: 2, x: 0.19, y: 0.22),
                PegAnchor(noteIndex: 3, x: 0.25, y: 0.10)
            ]
        case .ukulele:
            return [
                PegAnchor(noteIndex: 0, x: 0.065, y: 0.52),
                PegAnchor(noteIndex: 1, x: 0.065, y: 0.32),
                PegAnchor(noteIndex: 2, x: 0.89, y: 0.32),
                PegAnchor(noteIndex: 3, x: 0.89, y: 0.52)
            ]
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
        .scaleEffect(pegScale(for: viewModel.currentInstrument.type))
        .onTapGesture {
            viewModel.setTargetNote(note)
        }
    }

    private func pegScale(for type: InstrumentType) -> CGFloat {
        switch type {
        case .guitar7, .guitar8:
            return 0.80
        case .guitar6:
            return 0.86
        case .bass:
            return 0.88
        case .ukulele:
            return 0.92
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
    TunerView(initialInstrument: InstrumentCatalog.guitar6)
}

#Preview("7-String") {
    TunerView(initialInstrument: InstrumentCatalog.guitar7)
}

#Preview("Bass") {
    TunerView(initialInstrument: InstrumentCatalog.bass4)
}

#Preview("Ukulele") {
    TunerView(initialInstrument: InstrumentCatalog.ukulele4)
}

#Preview("Dark") {
    TunerView(initialInstrument: InstrumentCatalog.guitar6)
        .preferredColorScheme(.dark)
}
