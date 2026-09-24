import Foundation
import AVFoundation
import Observation

enum MicrophonePermission {
    /// The system prompt has not been shown yet — asking is still possible.
    case undetermined
    /// The user said no. Only a trip to Settings can change this.
    case denied
    case granted
}

@Observable
final class PermissionManager {
    private(set) var microphonePermission: MicrophonePermission = .undetermined

    var isMicrophoneGranted: Bool { microphonePermission == .granted }

    /// True when asking would show the system prompt. Once denied, the only route
    /// is Settings, and the UI has to say so instead of offering a prompt.
    var canRequestMicrophoneAccess: Bool { microphonePermission == .undetermined }

    init() {
        refreshMicrophonePermission()
    }

    /// Must be re-read whenever the app returns to the foreground: the user can
    /// grant access in Settings and come back, and the app would otherwise keep
    /// behaving as if it were still denied.
    func refreshMicrophonePermission() {
        microphonePermission = Self.currentPermission()
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        guard canRequestMicrophoneAccess else {
            completion(isMicrophoneGranted)
            return
        }

        // The main-actor task keeps the manager alive only until the user answers.
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            microphonePermission = granted ? .granted : .denied
            completion(granted)
        }
    }

    private static func currentPermission() -> MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
}
