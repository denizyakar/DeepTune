import SwiftUI

struct ManualStrobeArea: View {
    let centsDistance: Float
    let detectedNote: DetectedNote?
    let isSignalDetected: Bool
    
    private let maxVisualOffset: CGFloat = 96.0
    private let visualRangeCents: Float = 50.0
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.92))
                    .frame(height: 88)
                
                HStack(spacing: 14) {
                    ForEach(0..<11, id: \.self) { index in
                        Rectangle()
                            .fill(index == 5 ? Color.clear : Color.white.opacity(0.07))
                            .frame(width: 1, height: 56)
                    }
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2, height: 88)
                
                Rectangle()
                    .fill(isSignalDetected ? Color.cyan : Color.gray)
                    .frame(width: 4, height: 64)
                    .offset(x: clampedOffset)
                    .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.75), value: centsDistance)
                
                noteBadge
                
                if !isSignalDetected {
                    Text("NO SIGNAL")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(5)
                        .offset(y: 28)
                }
            }
            
            Text(String(format: "%.1f cents", centsDistance))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSignalDetected ? .white : .gray)
        }
    }
    
    private var noteBadge: some View {
        Group {
            if let detectedNote {
                Text("\(detectedNote.name)\(detectedNote.octave)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(isSignalDetected ? .cyan : .gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            } else {
                Text("--")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var clampedOffset: CGFloat {
        let normalized = CGFloat(centsDistance / visualRangeCents)
        return max(-maxVisualOffset, min(maxVisualOffset, normalized * maxVisualOffset))
    }
}
