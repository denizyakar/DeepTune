import SwiftUI

struct StrobeTunerArea: View {
    @Binding var centsDistance: Float
    var targetNote: Note?
    var isTuningSuccessful: Bool
    
    // Limits how far the visual pitch indicator can go in pixels
    private let maxVisualOffset: CGFloat = 100.0
    
    var body: some View {
        VStack(spacing: 8) {
            
            // Strobe Container
            ZStack {
                // Dim Grid Area
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 80)
                
                // Fixed Grid Lines
                HStack(spacing: 15) {
                    ForEach(0..<9) { index in
                        Rectangle()
                            .fill(Color.white.opacity(index == 4 ? 0.0 : 0.05)) // Skip center
                            .frame(width: 1, height: 60)
                    }
                }
                
                // Fixed Center Target Line with Note Name
                ZStack {
                    Rectangle()
                        .fill(isTuningSuccessful ? Color.green : Color.yellow.opacity(0.8))
                        .frame(width: 2, height: 80)
                    
                    // Fixed Note name in the center (On top of the line)
                    if let targetNote = targetNote {
                        Text("\(targetNote.name)\(targetNote.octave)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(isTuningSuccessful ? .green : .yellow)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                
                // Dynamic Pitch Indicator (Moving left/right)
                // Maps cents (-50 to 50) to offset (-100 to 100)
                if abs(centsDistance) < 50.0 {
                    let offset = CGFloat(centsDistance) / 50.0 * maxVisualOffset
                    
                    Rectangle()
                        .fill(isTuningSuccessful ? Color.green : Color.white)
                        .frame(width: 4, height: 70)
                        .offset(x: min(max(offset, -maxVisualOffset), maxVisualOffset))
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: centsDistance)
                }
            }
            .padding(.horizontal, 40)
            
            // Success Feedback
            // Shows a checkmark briefly when in-tune duration threshold is met
            HStack {
                if isTuningSuccessful {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.scale)
                }
                
                Text(String(format: "%.1f cents", centsDistance))
                    .font(.subheadline)
                    .foregroundColor(isTuningSuccessful ? .green : .secondary)
            }
            .animation(.easeInOut, value: isTuningSuccessful)
        }
    }
}
