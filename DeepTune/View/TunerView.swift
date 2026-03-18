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
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    headerView
                    
                    Spacer()
                    
                    // 1. Strobe at the top
                    // Now includes the note name inside the center line
                    StrobeTunerArea(
                        centsDistance: $viewModel.centsDistance,
                        targetNote: viewModel.targetNote,
                        isTuningSuccessful: viewModel.isTuningSuccessful
                    )
                    
                    // 2. Main White Box (Headstock)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 30)
                            .fill(Color.white)
                            .frame(width: 340, height: 450)
                            .shadow(radius: 10)
                        
                        VStack(spacing: 0) {
                            
                            // Top Right: Auto Progression Toggle
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    viewModel.isAutoProgressEnabled.toggle()
                                }) {
                                    HStack {
                                        Text("Auto")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Image(systemName: viewModel.isAutoProgressEnabled ? "checkmark.circle.fill" : "circle")
                                    }
                                    .foregroundColor(viewModel.isAutoProgressEnabled ? .green : .gray)
                                    .padding(8)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(8)
                                }
                                .padding(.trailing, 20)
                                .padding(.top, 20)
                            }
                            
                            Spacer()
                            
                            // Headstock Image & Buttons Area
                            headstockView
                            
                            Spacer()
                        }
                    }
                    
                    Spacer()
                }
            }
            .tabItem {
                            Label("Auto", systemImage: "guitars")
                        }
                        .onAppear {
                            if viewModel.targetNote == nil {
                                viewModel.setTargetNote(viewModel.currentTuning.notes.first)
                            }
                        }
            
            // MARK: - Manual Mode Tab
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    headerView
                    
                    Spacer()
                    
                    StrobeTunerArea(
                        centsDistance: $viewModel.centsDistance,
                        targetNote: viewModel.targetNote,
                        isTuningSuccessful: viewModel.isTuningSuccessful
                    )
                    
                    Text(String(format: "%.1f cents", viewModel.centsDistance))
                        .font(.headline)
                        .foregroundColor(abs(viewModel.centsDistance) < 5.0 ? .green : .secondary)
                        .padding(.bottom, 10)
                    
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 30)
                            .fill(Color.white)
                            .frame(width: 340, height: 450)
                            .shadow(radius: 10)
                        
                        VStack(spacing: 15) {
                            HStack(alignment: .lastTextBaseline) {
                                Text(viewModel.targetNote?.name ?? "--")
                                    .font(.system(size: 80, weight: .black, design: .rounded))
                                    .foregroundColor(abs(viewModel.centsDistance) < 5.0 ? .green : .black)
                                
                                if let octave = viewModel.targetNote?.octave {
                                    Text(String(octave))
                                        .font(.title)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.top, 20)
                            
                            Spacer()
                            
                            // Manual Instruction inside the box
                            Text("Play a string or sing a note.\nThe tuner will focus on the closest pitch.")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding()
                            
                            Spacer()
                        }
                    }
                    
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
    
    // Simulated Headstock layout for Auto Mode (Inside the white box)
        private var headstockView: some View {
            ZStack {
                // Placeholder space for the future guitar headstock image
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 140, height: 280)
                    .overlay(Text("Headstock\nImage\nArea").foregroundColor(.gray).multilineTextAlignment(.center))
                
                let notes = viewModel.currentTuning.notes
                
                // Positioning 6 strings (3 left, 3 right)
                if notes.count == 6 {
                    HStack(spacing: 70) { // Spread out to fit around the image
                        // Left Side (Thick strings: 6th, 5th, 4th)
                        VStack(spacing: 30) {
                            PegButton(note: notes[0], isActive: viewModel.targetNote == notes[0], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[0]) } // <-- Dokunma eklendi
                            
                            PegButton(note: notes[1], isActive: viewModel.targetNote == notes[1], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[1]) } // <-- Dokunma eklendi
                            
                            PegButton(note: notes[2], isActive: viewModel.targetNote == notes[2], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[2]) } // <-- Dokunma eklendi
                        }
                        
                        // Right Side (Thin strings: 3rd, 2nd, 1st)
                        VStack(spacing: 30) {
                            PegButton(note: notes[3], isActive: viewModel.targetNote == notes[3], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[3]) } // <-- Dokunma eklendi
                            
                            PegButton(note: notes[4], isActive: viewModel.targetNote == notes[4], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[4]) } // <-- Dokunma eklendi
                            
                            PegButton(note: notes[5], isActive: viewModel.targetNote == notes[5], isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(notes[5]) } // <-- Dokunma eklendi
                        }
                    }
                } else {
                    // Fallback for non-6-string
                    HStack {
                        ForEach(notes) { note in
                            PegButton(note: note, isActive: viewModel.targetNote == note, isDarkTheme: false)
                                .onTapGesture { viewModel.setTargetNote(note) } // <-- Dokunma eklendi
                        }
                    }
                }
            }
            .frame(height: 300)
        }
}

// Subcomponent for Tuning Pegs
struct PegButton: View {
    var note: Note
    var isActive: Bool
    var isDarkTheme: Bool = true // Used to switch colors depending on background
    
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
    }
}

#Preview {
    TunerView()
}
