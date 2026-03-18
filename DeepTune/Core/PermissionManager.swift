import Foundation
import AVFoundation
import Combine

final class PermissionManager: ObservableObject {
    @Published var isMicrophoneGranted: Bool = false
    
    init() {
        checkMicrophonePermission()
    }
    
    func checkMicrophonePermission() {
        let isGranted: Bool
        if #available(iOS 17.0, *) {
            isGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            isGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        }
        
        if isGranted {
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = true
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isMicrophoneGranted = false
            }
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { [weak self] in
                    self?.isMicrophoneGranted = granted
                    completion(granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { [weak self] in
                    self?.isMicrophoneGranted = granted
                    completion(granted)
                }
            }
        }
    }
}
