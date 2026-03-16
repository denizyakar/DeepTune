import SwiftUI

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    func playSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func playLightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
