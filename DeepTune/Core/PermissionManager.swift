import Foundation
import AVFoundation
import Combine

enum MicrophonePermission {
    /// The system prompt has not been shown yet — asking is still possible.
    case undetermined
    /// The user said no. Only a trip to Settings can change this.
    case denied
    case granted
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphonePermission: MicrophonePermission = .undetermined

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

        let handler: @Sendable (Bool) -> Void = { granted in
            Task { @MainActor [weak self] in
                self?.microphonePermission = granted ? .granted : .denied
                completion(granted)
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handler)
        }
    }

    private static func currentPermission() -> MicrophonePermission {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }
}
