import SwiftUI

private enum TunerTab: Hashable {
    case auto
    case manual
    case chord
}

struct TunerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var session: TunerSession
    @State private var autoTuner: AutoTunerViewModel
    @State private var manualTuner: ManualTunerViewModel
    @State private var permissionManager: PermissionManager

    @State private var showSettings = false
    @State private var showInstrumentPicker = false
    @State private var showTuningPicker = false
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
                requiringMicrophone {
                    AutoTunerView(model: autoTuner, header: header)
                }
                .tabItem {
                    Label("Auto", systemImage: "guitars")
                }
                .tag(TunerTab.auto)
                .onAppear {
                    if autoTuner.targetNote == nil {
                        autoTuner.setTargetNote(session.currentTuning.notes.first)
                    }
                }

                requiringMicrophone {
                    ManualTunerView(model: manualTuner, header: header)
                }
                .tabItem {
                    Label("Manual", systemImage: "waveform.path")
                }
                .tag(TunerTab.manual)

                requiringMicrophone {
                    ChordTabView(session: session, isSessionActive: $isChordFinderSessionActive, header: header)
                }
                .tabItem {
                    Label("Chord", systemImage: "music.note")
                }
                .tag(TunerTab.chord)
            }
        }
        .tint(AppTheme.accent)
        .onAppear {
            // Onboarding asks for the microphone; a user who declined there gets
            // the in-tab card instead of a second prompt.
            applyAudioTrackingMode(for: selectedTab)
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
            UIApplication.shared.isIdleTimerDisabled = false
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
    }

    /// Every tab needs the microphone, so without it the tab explains why
    /// instead of showing a tuner that can never react.
    @ViewBuilder
    private func requiringMicrophone<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if permissionManager.isMicrophoneGranted {
            content()
        } else {
            MicrophoneAccessView(
                permission: permissionManager.microphonePermission,
                header: header,
                onRequestAccess: ensureMicrophonePermission
            )
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
        let shouldRun = shouldRunAudioEngine
        if shouldRun {
            session.start()
        } else {
            session.stop()
        }
        // Both hands are on the instrument while tuning, so the screen would
        // otherwise lock mid-session. Set here so it can never outlive the engine.
        UIApplication.shared.isIdleTimerDisabled = shouldRun
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
                // Settings can change it, and the tab already says why.
                if permissionManager.canRequestMicrophoneAccess {
                    ensureMicrophonePermission()
                } else if !permissionManager.isMicrophoneGranted,
                          let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
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
