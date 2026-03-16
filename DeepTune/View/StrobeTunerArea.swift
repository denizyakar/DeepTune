import SwiftUI

struct StrobeTunerArea: View {
    @Binding var centsDistance: Float
    var targetNote: Note?
    
    var body: some View {
        VStack {
            // "Space-time" Strobe effect
            ZStack {
                // Background grid / space-time area
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.8))
                    .frame(height: 120)
                
                // Grid lines (abstract)
                HStack(spacing: 20) {
                    ForEach(0..<10) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1)
                    }
                }
                
                // Target Line (Perfect Pitch)
                Rectangle()
                    .fill(Color.yellow.opacity(0.5))
                    .frame(width: 2, height: 100)
                
                // Moving particle / bar based on cents
                GeometryReader { geometry in
                    let center = geometry.size.width / 2
                    // Map -50...+50 cents
                    let offset = CGFloat(centsDistance) / 50.0 * (center - 20)
                    
                    Rectangle()
                        .frame(width: 8, height: 80)
                        .foregroundColor(abs(centsDistance) < 5.0 ? .green : .cyan)
                        .cornerRadius(4)
                        .shadow(color: abs(centsDistance) < 5.0 ? .green : .cyan, radius: 10, x: 0, y: 0)
                        .position(x: center + offset, y: geometry.size.height / 2)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: centsDistance)
                }
            }
            .padding(.horizontal)
            
            // Note Display
            HStack(alignment: .lastTextBaseline) {
                Text(targetNote?.name ?? "--")
                    .font(.system(size: 70, weight: .black, design: .rounded))
                    .foregroundColor(abs(centsDistance) < 5.0 ? .green : .primary)
                
                if let octave = targetNote?.octave {
                    Text(String(octave))
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(String(format: "%.1f cents", centsDistance))
                .font(.headline)
                .foregroundColor(abs(centsDistance) < 5.0 ? .green : .secondary)
        }
    }
}
