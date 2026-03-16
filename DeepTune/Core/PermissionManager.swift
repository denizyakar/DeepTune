import Foundation
import AVFoundation
import Combine

class PermissionManager: ObservableObject {
    @Published var isMicrophoneGranted: Bool = false
    
    init() {
        checkMicrophonePermission()
    }
    
    func checkMicrophonePermission() {
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .granted:
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = true
            }
        case .denied, .undetermined:
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = false
            }
        @unknown default:
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = false
            }
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = granted
                completion(granted)
            }
        }
    }
}
