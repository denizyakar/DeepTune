import SwiftUI

struct AutoStrobeArea: View {
    let centsDistance: Float
    let targetNote: Note?
    let isTuningSuccessful: Bool
    let isSignalDetected: Bool
    let hasPitchReference: Bool
    let tuneProgressRatio: Double
    
    private let maxVisualOffset: CGFloat = 92.0
    private let visualRangeCents: Float = 50.0
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.92))
                    .frame(height: 58)
                
                HStack(spacing: 13) {
                    ForEach(0..<11, id: \.self) { index in
                        Rectangle()
                            .fill(index == 5 ? Color.clear : Color.white.opacity(0.08))
                            .frame(width: 1, height: 34)
                    }
                }
                
                Rectangle()
                    .fill(isTuningSuccessful ? Color.green : Color.yellow)
                    .frame(width: 2, height: 58)
                
                if let targetNote {
                    Text("\(targetNote.name)\(targetNote.octave)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(isTuningSuccessful ? .green : .yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(6)
                }
                
                // Clamps the indicator to the edges so users still get direction feedback when very far off-target.
                if hasPitchReference {
                    Rectangle()
                        .fill(isTuningSuccessful ? Color.green : (isSignalDetected ? Color.white : Color.white.opacity(0.55)))
                        .frame(width: 4, height: 44)
                        .offset(x: clampedOffset)
                        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.75), value: centsDistance)
                }
                
                if !isSignalDetected {
                    Text("NO SIGNAL")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(5)
                        .offset(y: 18)
                }
            }
            
            Text(String(format: "%.1f cents", centsDistance))
                .font(.caption)
                .foregroundColor(isTuningSuccessful ? .green : (isSignalDetected ? .gray : .gray.opacity(0.7)))
            
            ProgressView(value: tuneProgressRatio)
                .progressViewStyle(.linear)
                .tint(isTuningSuccessful ? .green : .yellow)
                .opacity(isSignalDetected || tuneProgressRatio > 0 ? 1.0 : 0.45)
        }
    }
    
    private var clampedOffset: CGFloat {
        let normalized = CGFloat(centsDistance / visualRangeCents)
        return max(-maxVisualOffset, min(maxVisualOffset, normalized * maxVisualOffset))
    }
}
