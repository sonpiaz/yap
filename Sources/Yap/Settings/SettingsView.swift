import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    // Provider
    @AppStorage("sttProvider") private var sttProvider = STTProviderType.groq.rawValue
    @AppStorage("groqApiKey") private var groqApiKey = ""
    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @AppStorage("deepgramApiKey") private var deepgramApiKey = ""

    // Language
    @AppStorage("sttLanguage") private var sttLanguage = STTLanguage.auto.rawValue

    // Behavior
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    private var selectedProvider: STTProviderType {
        STTProviderType(rawValue: sttProvider) ?? .groq
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            providerTab
                .tabItem { Label("Provider", systemImage: "cloud") }

            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 340)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Behavior") {
                Toggle("Auto-paste into active text field", isOn: $autoPaste)
                    .onChange(of: autoPaste) { _, newValue in
                        if newValue {
                            TextInserter.requestAccessibilityIfNeeded()
                        }
                    }

                Text("When enabled, transcriptions are pasted directly into the app you're using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("[Yap] Launch at login error: \(error)")
                        }
                    }
            }

            Section("History") {
                Button("Clear All Transcriptions") {
                    AppState.shared.transcriptions.removeAll()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Provider Tab

    private var providerTab: some View {
        Form {
            Section("Speech-to-Text Provider") {
                Picker("Provider", selection: $sttProvider) {
                    ForEach(STTProviderType.allCases) { provider in
                        VStack(alignment: .leading) {
                            Text(provider.rawValue)
                        }
                        .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(selectedProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API Key — \(selectedProvider.rawValue)") {
                switch selectedProvider {
                case .groq:
                    SecureField("gsk_...", text: $groqApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get a free key at console.groq.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .openai:
                    SecureField("sk-proj-...", text: $openaiApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get a key at platform.openai.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .deepgram:
                    SecureField("dg_...", text: $deepgramApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("$200 free credits at deepgram.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Language") {
                Picker("Language", selection: $sttLanguage) {
                    ForEach(STTLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Hotkey Tab

    private var hotkeyTab: some View {
        Form {
            Section("Push-to-Talk") {
                KeyboardShortcuts.Recorder("Hotkey", name: .pushToTalk)
                Text("Hold to record, release to transcribe and paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
