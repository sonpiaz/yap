import SwiftUI

@main
struct YapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .frame(width: 380, height: 440)
        } label: {
            Label("Yap", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private var menuBarIcon: String {
        if state.isRecording {
            return "record.circle.fill"
        } else if state.isTranscribing {
            return "ellipsis.circle"
        } else {
            return "waveform.circle"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults FIRST
        UserDefaults.standard.register(defaults: [
            "autoPaste": true,
            "outputMode": OutputMode.pasteOnly.rawValue,
            "sttProvider": STTProviderType.groq.rawValue,
            "sttLanguage": STTLanguage.auto.rawValue,
            "recordingMode": RecordingMode.holdToTalk.rawValue,
            "noiseSuppression": true,
        ])

        if UserDefaults.standard.string(forKey: "pushToTalkTriggerData") == nil {
            PushToTalkTrigger.saveToDefaults(.defaultValue)
        }

        // Setup hotkey
        HotkeyManager.shared.setup()

        // Request Accessibility for auto-paste (non-blocking)
        if UserDefaults.standard.bool(forKey: "autoPaste") {
            TextInserter.requestAccessibilityIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

}
