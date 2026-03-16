import SwiftUI

struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    @StateObject private var permissionManager = PermissionManager()
    
    @State private var showSettings = false
    @State private var showTuningPicker = false
    @State private var showPermissionAlert = false
    
    var body: some View {
        TabView {
            // MARK: - Auto Mode Tab (Headstock)
            ZStack {
                Color.black.ignoresSafeArea() // Deep theme
                
                VStack(spacing: 20) {
                    headerView
                    Spacer()
                    StrobeTunerArea(
                        centsDistance: $viewModel.centsDistance,
                        targetNote: viewModel.targetNote
                    )
                    Spacer()
                    headstockView
                    Spacer()
                }
            }
            .tabItem {
                Label("Auto", systemImage: "guitars")
            }
            .onAppear {
                viewModel.setTargetNote(nil) // Auto mode
            }
            
            // MARK: - Manual Mode Tab
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    headerView
                    Spacer()
                    StrobeTunerArea(
                        centsDistance: $viewModel.centsDistance,
                        targetNote: viewModel.targetNote
                    )
                    Spacer()
                    manualSelectionView
                    Spacer()
                }
            }
            .tabItem {
                Label("Manual", systemImage: "hand.tap")
            }
        }
        .onAppear {
            permissionManager.requestMicrophonePermission { granted in
                if granted {
                    viewModel.start()
                }
            }
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
    
    // MARK: - Subviews
    private var headerView: some View {
        HStack {
            Button(action: { showTuningPicker.toggle() }) {
                Text("\(viewModel.currentInstrument.name) - \(viewModel.currentTuning.name)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
            }
            
            Spacer()
            
            Button(action: {
                if !permissionManager.isMicrophoneGranted { showPermissionAlert = true }
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
        .padding()
    }
    
    // Simulated Headstock layout for Auto Mode
    // Places buttons in a 3x3 array alongside an invisible/placeholder image for the future
    private var headstockView: some View {
        ZStack {
            // Placeholder space for the future guitar headstock image
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white.opacity(0.05))
                .frame(width: 140, height: 300)
                .overlay(Text("Headstock\nImage").foregroundColor(.gray).multilineTextAlignment(.center))
            
            let notes = viewModel.currentTuning.notes
            
            // Positioning 6 strings (3 left, 3 right)
            if notes.count == 6 {
                HStack(spacing: 60) {
                    // Left Side (Thick strings: 6th, 5th, 4th)
                    VStack(spacing: 40) {
                        PegButton(note: notes[0], isActive: viewModel.targetNote == notes[0])
                        PegButton(note: notes[1], isActive: viewModel.targetNote == notes[1])
                        PegButton(note: notes[2], isActive: viewModel.targetNote == notes[2])
                    }
                    
                    // Right Side (Thin strings: 3rd, 2nd, 1st)
                    VStack(spacing: 40) {
                        PegButton(note: notes[3], isActive: viewModel.targetNote == notes[3])
                        PegButton(note: notes[4], isActive: viewModel.targetNote == notes[4])
                        PegButton(note: notes[5], isActive: viewModel.targetNote == notes[5])
                    }
                }
            } else {
                // Fallback for non-6-string (just horizontal list for now)
                HStack {
                    ForEach(notes) { note in
                        PegButton(note: note, isActive: viewModel.targetNote == note)
                    }
                }
            }
        }
        .frame(height: 350)
    }
    
    // Manual String Selection
    private var manualSelectionView: some View {
        VStack {
            Text("Tap a string to tune manually.")
                .foregroundColor(.gray)
                .padding(.bottom)
            
            HStack(spacing: 15) {
                ForEach(viewModel.currentTuning.notes) { note in
                    Button(action: {
                        if viewModel.targetNote == note {
                            viewModel.setTargetNote(nil)
                        } else {
                            viewModel.setTargetNote(note)
                        }
                    }) {
                        Text(note.name)
                            .font(.title3)
                            .frame(width: 50, height: 50)
                            .background(viewModel.targetNote == note ? Color.blue : Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .frame(height: 350)
    }
}

// Subcomponent for Tuning Pegs
struct PegButton: View {
    var note: Note
    var isActive: Bool
    
    var body: some View {
        Text(note.name)
            .font(.headline)
            .bold()
            .frame(width: 50, height: 50)
            .background(
                Circle()
                    .fill(isActive ? Color.green : Color.white.opacity(0.1))
                    .shadow(color: isActive ? .green : .clear, radius: 10)
            )
            .foregroundColor(.white)
            .animation(.spring(), value: isActive)
    }
}

#Preview {
    TunerView()
}
