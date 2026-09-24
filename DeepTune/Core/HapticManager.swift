import SwiftUI

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    func playSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
