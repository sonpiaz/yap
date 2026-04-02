import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("claudeApiKey") private var claudeApiKey = ""
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Push-to-talk key", name: .pushToTalk)
                Text("Hold to record, release to transcribe and paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Mode") {
                Picker("Transcription mode", selection: $appState.currentMode) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                            Text("— \(mode.description)")
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Smart Mode (Claude API)") {
                SecureField("Claude API key", text: $claudeApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Optional. Used in Smart mode for context-aware formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Yap")
                .font(.title)
                .fontWeight(.bold)

            Text("v0.2.0")
                .foregroundStyle(.secondary)

            Text("Push-to-talk dictation for Mac")
                .font(.callout)

            Text("Apple Speech • Vi/En support • Local + Fast")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Link("GitHub: sonpiaz/yap",
                 destination: URL(string: "https://github.com/sonpiaz/yap")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
