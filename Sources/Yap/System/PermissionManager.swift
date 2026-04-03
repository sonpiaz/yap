import Foundation
import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    enum Status: String {
        case granted = "Granted"
        case denied = "Not Granted"
        case unknown = "Unknown"

        var symbolName: String {
            switch self {
            case .granted: return "checkmark.circle.fill"
            case .denied: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }
    }

    @Published private(set) var microphoneStatus: Status = .unknown
    @Published private(set) var accessibilityStatus: Status = .unknown
    @Published private(set) var inputMonitoringStatus: Status = .unknown

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        microphoneStatus = Self.mapMicrophoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
        inputMonitoringStatus = canUseInputMonitoring() ? .granted : .denied
    }

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        refresh()
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func canUseInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    private static func mapMicrophoneStatus(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }
}
