import AppKit
import AVFoundation
import ApplicationServices

enum PermissionsManager {
    static var cameraStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static var hasCameraPermission: Bool {
        cameraStatus == .authorized
    }

    static func requestCamera(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasAllRequired: Bool {
        hasCameraPermission && hasAccessibility
    }

    static func openAccessibilityPrefs() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openCameraPrefs() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
