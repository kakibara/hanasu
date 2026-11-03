import AppKit
import ApplicationServices
import AVFoundation
import Speech

enum PermissionError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "マイクの使用が許可されていません（システム設定 → プライバシーとセキュリティ → マイク）"
        case .speechRecognitionDenied: "音声認識が許可されていません（システム設定 → プライバシーとセキュリティ → 音声認識）"
        }
    }
}

enum Permissions {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var speechStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // 設計判断: DEC-COM-014
    /// 録音に必要な権限（マイク・音声認識）を、未決定なら尋ね、拒否されていればエラーにする。
    /// Whisper / Gemini で文字起こしするときは、音声認識の権限は要らない（speechRecognition: false）
    static func ensureRecordingPermissions(speechRecognition: Bool = true) async throws {
        switch microphoneStatus {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw PermissionError.microphoneDenied }
        default:
            throw PermissionError.microphoneDenied
        }
        guard speechRecognition else { return }

        switch speechStatus {
        case .authorized: break
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { throw PermissionError.speechRecognitionDenied }
        default:
            throw PermissionError.speechRecognitionDenied
        }
    }

    static func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
