import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("claudeApiKey") private var claudeApiKey = ""
    @AppStorage("ollamaModel") private var ollamaModel = "qwen2.5:14b"
    @AppStorage("whisperModel") private var whisperModel = "large-v3"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var ollamaStatus = "Checking..."

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 350)
        .onAppear { checkOllama() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Text("Hold **Right Option (⌥)** to record")
                    .font(.callout)
                Text("Release to transcribe and paste")
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

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Models

    private var modelsTab: some View {
        Form {
            Section("Speech-to-Text (WhisperKit)") {
                Picker("Whisper model", selection: $whisperModel) {
                    Text("large-v3 (best accuracy, ~3GB)").tag("large-v3")
                    Text("small (balanced, ~500MB)").tag("small")
                    Text("base (fastest, ~150MB)").tag("base")
                }
                Text("large-v3 recommended for Vietnamese + English")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("LLM Cleanup") {
                HStack {
                    Text("Ollama")
                    Spacer()
                    Text(ollamaStatus)
                        .foregroundStyle(ollamaStatus == "Connected" ? .green : .orange)
                    Button("Refresh") { checkOllama() }
                        .buttonStyle(.borderless)
                }

                TextField("Ollama model", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)

                Divider()

                SecureField("Claude API key (fallback)", text: $claudeApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used when Ollama unavailable. Uses claude-haiku-4-5 for speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Text("v0.1.0")
                .foregroundStyle(.secondary)

            Text("Push-to-talk dictation for Mac")
                .font(.callout)

            Text("Local Whisper • Vi/En mixing • LLM cleanup")
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

    private func checkOllama() {
        Task {
            do {
                let url = URL(string: "http://localhost:11434/api/tags")!
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    ollamaStatus = "Connected"
                } else {
                    ollamaStatus = "Not running"
                }
            } catch {
                ollamaStatus = "Not running"
            }
        }
    }
}
