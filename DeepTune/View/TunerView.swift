import SwiftUI

struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    @StateObject private var permissionManager = PermissionManager()
    
    @State private var showSettings = false
    @State private var showTuningPicker = false
    @State private var showPermissionAlert = false
    @State private var selectedMode: TunerMode = .auto
    
    var body: some View {
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
                    Label("Manual", systemImage: "hand.tap")
                }
                .tag(TunerMode.manual)
        }
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
    
    // Keeps Auto mode focused on target-string tuning and progression.
    private var autoModeView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 14) {
                headerView
                
                autoPanel
                
                Spacer(minLength: 0)
            }
        }
    }
    
    // Keeps Manual mode independent from selected string and target note.
    private var manualModeView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 18) {
                headerView
                
                ManualStrobeArea(
                    centsDistance: viewModel.manualCentsDistance,
                    detectedNote: viewModel.detectedNote,
                    isSignalDetected: viewModel.isSignalDetected
                )
                .padding(.horizontal, 20)
                
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white)
                    .overlay(manualInfoPanel.padding(.top, 26))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                
                Spacer(minLength: 0)
            }
        }
    }
    
    private var autoPanel: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
            
            VStack(spacing: 18) {
                AutoStrobeArea(
                    centsDistance: viewModel.autoCentsDistance,
                    targetNote: viewModel.targetNote,
                    isTuningSuccessful: viewModel.isTuningSuccessful,
                    isSignalDetected: viewModel.isTargetSignalDetected,
                    hasPitchReference: viewModel.hasPitchReference,
                    tuneProgressRatio: viewModel.tuneProgressRatio
                )
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                headstockView
                    .padding(.bottom, 20)
            }
            
            Button(action: { viewModel.isAutoProgressEnabled.toggle() }) {
                HStack(spacing: 8) {
                    Text("Auto")
                        .font(.subheadline.weight(.bold))
                    Image(systemName: viewModel.isAutoProgressEnabled ? "checkmark.circle.fill" : "circle")
                }
                .foregroundColor(viewModel.isAutoProgressEnabled ? .green : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.08))
                .cornerRadius(12)
            }
            .padding(.top, 18)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 540, maxHeight: 600)
        .padding(.horizontal, 20)
    }
    
    private var manualInfoPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(viewModel.detectedNote?.name ?? "--")
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .foregroundColor(viewModel.isSignalDetected ? .black : .gray)
                
                Text(viewModel.detectedNote.map { "\($0.octave)" } ?? "")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.gray)
            }
            
            Text(
                viewModel.detectedNote.map { String(format: "Nearest %.2f Hz", $0.nearestFrequency) }
                ?? "Play a note to detect frequency"
            )
            .font(.subheadline.weight(.medium))
            .foregroundColor(.gray)
            
            Text("Manual mode tracks the note you play, not the selected string.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
            
            Spacer(minLength: 0)
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { showTuningPicker.toggle() }) {
                Text("\(viewModel.currentInstrument.name) - \(viewModel.currentTuning.name)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            
            Spacer()
            
            Button(action: {
                if !permissionManager.isMicrophoneGranted {
                    showPermissionAlert = true
                }
            }) {
                Image(systemName: permissionManager.isMicrophoneGranted ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .foregroundColor(permissionManager.isMicrophoneGranted ? .green : .red)
            }
            .padding(.trailing, 8)
            
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
    
    // Mirrors a realistic 6-string headstock peg layout and keeps direct string selection fast.
    private var headstockView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.05))
                .frame(width: 140, height: 280)
                .overlay(
                    Text("Headstock\nImage\nArea")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                )
            
            let notes = viewModel.currentTuning.notes
            
            if notes.count == 6 {
                HStack(spacing: 70) {
                    VStack(spacing: 30) {
                        PegButton(
                            note: notes[0],
                            isActive: viewModel.targetNote == notes[0],
                            isCompleted: viewModel.isNoteCompleted(notes[0]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[0]) }
                        PegButton(
                            note: notes[1],
                            isActive: viewModel.targetNote == notes[1],
                            isCompleted: viewModel.isNoteCompleted(notes[1]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[1]) }
                        PegButton(
                            note: notes[2],
                            isActive: viewModel.targetNote == notes[2],
                            isCompleted: viewModel.isNoteCompleted(notes[2]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[2]) }
                    }
                    
                    VStack(spacing: 30) {
                        PegButton(
                            note: notes[3],
                            isActive: viewModel.targetNote == notes[3],
                            isCompleted: viewModel.isNoteCompleted(notes[3]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[3]) }
                        PegButton(
                            note: notes[4],
                            isActive: viewModel.targetNote == notes[4],
                            isCompleted: viewModel.isNoteCompleted(notes[4]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[4]) }
                        PegButton(
                            note: notes[5],
                            isActive: viewModel.targetNote == notes[5],
                            isCompleted: viewModel.isNoteCompleted(notes[5]),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(notes[5]) }
                    }
                }
            } else {
                HStack {
                    ForEach(notes) { note in
                        PegButton(
                            note: note,
                            isActive: viewModel.targetNote == note,
                            isCompleted: viewModel.isNoteCompleted(note),
                            isDarkTheme: false
                        )
                            .onTapGesture { viewModel.setTargetNote(note) }
                    }
                }
            }
        }
        .frame(height: 300)
    }
}

struct PegButton: View {
    var note: Note
    var isActive: Bool
    var isCompleted: Bool = false
    var isDarkTheme: Bool = true
    
    var body: some View {
        Text(note.name)
            .font(.headline)
            .bold()
            .frame(width: 45, height: 45)
            .background(
                Circle()
                    .fill(isActive ? Color.green : (isDarkTheme ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                    .shadow(color: isActive ? .green.opacity(0.5) : .clear, radius: 5)
            )
            .foregroundColor(isActive ? .white : (isDarkTheme ? .white : .black))
            .animation(.spring(), value: isActive)
            .overlay(alignment: .topTrailing) {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                        .background(Circle().fill(Color.white))
                        .offset(x: 4, y: -4)
                }
            }
    }
}

#Preview {
    TunerView()
}
