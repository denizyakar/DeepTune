import SwiftUI

private enum TunerTab: Hashable {
    case auto
    case manual
    case chord
}

struct TunerView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var session: TunerSession
    @State private var autoTuner: AutoTunerViewModel
    @State private var manualTuner: ManualTunerViewModel
    @State private var permissionManager: PermissionManager

    @State private var showSettings = false
    @State private var showInstrumentPicker = false
    @State private var showTuningPicker = false
    @State private var showPermissionAlert = false
    @State private var selectedTab: TunerTab = .auto
    @State private var isChordFinderSessionActive = false

    /// Nil restores the user's last selection; previews pass one to pin it.
    init(initialInstrument: Instrument? = nil) {
        // Unlike StateObject, State builds these eagerly on every init. That is fine
        // only because TunerView is the root screen and its parent never re-renders.
        let session = TunerSession(instrument: initialInstrument)
        _session = State(initialValue: session)
        _autoTuner = State(initialValue: AutoTunerViewModel(session: session))
        _manualTuner = State(initialValue: ManualTunerViewModel(session: session))
        _permissionManager = State(initialValue: PermissionManager())
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                AutoTunerView(model: autoTuner, header: header)
                    .tabItem {
                        Label("Auto", systemImage: "guitars")
                    }
                    .tag(TunerTab.auto)
                    .onAppear {
                        if autoTuner.targetNote == nil {
                            autoTuner.setTargetNote(session.currentTuning.notes.first)
                        }
                    }

                ManualTunerView(model: manualTuner, header: header)
                    .tabItem {
                        Label("Manual", systemImage: "waveform.path")
                    }
                    .tag(TunerTab.manual)

                ChordTabView(session: session, isSessionActive: $isChordFinderSessionActive, header: header)
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
        .onChange(of: scenePhase) { _, newPhase in
            // The user may have granted access in Settings while the app was away.
            if newPhase == .active {
                permissionManager.refreshMicrophonePermission()
            }
            synchronizeAudioState()
        }
        .onChange(of: isChordFinderSessionActive) { _, _ in
            synchronizeAudioState()
        }
        .onDisappear {
            session.stop()
        }
        .task {
            await session.processPitchUpdates()
        }
        .sheet(isPresented: $showInstrumentPicker) {
            InstrumentPickerView(session: session)
        }
        .sheet(isPresented: $showTuningPicker) {
            TuningPickerView(session: session)
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
            session.start()
        } else {
            session.stop()
        }
    }

    private func ensureMicrophonePermission() {
        guard permissionManager.canRequestMicrophoneAccess else { return }
        permissionManager.requestMicrophonePermission { _ in
            synchronizeAudioState()
        }
    }

    private func applyAudioTrackingMode(for tab: TunerTab) {
        switch tab {
        case .auto:
            session.setActiveMode(.auto)
        case .manual, .chord:
            session.setActiveMode(.manual)
        }

        // Only the chord finder reads the raw sample window.
        session.setRecentAudioCaptureEnabled(tab == .chord)
    }

    private var header: TunerHeaderView {
        TunerHeaderView(
            instrument: session.currentInstrument,
            tuning: session.currentTuning,
            isMicrophoneGranted: permissionManager.isMicrophoneGranted,
            onInstrumentTap: { showInstrumentPicker.toggle() },
            onTuningTap: { showTuningPicker.toggle() },
            onMicrophoneTap: {
                // Never been asked: show the system prompt. Denied: only
                // Settings can help, so say that instead.
                if permissionManager.canRequestMicrophoneAccess {
                    ensureMicrophonePermission()
                } else if !permissionManager.isMicrophoneGranted {
                    showPermissionAlert = true
                }
            },
            onSettingsTap: { showSettings.toggle() }
        )
    }
}

private struct ChordTabView: View {
    let session: TunerSession
    @Binding var isSessionActive: Bool
    let header: TunerHeaderView

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    header
                        .frame(height: 88)

                    ChordFinderView(
                        session: session,
                        isSessionActive: $isSessionActive
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
