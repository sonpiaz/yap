import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var recorder = AudioRecorder.shared
    @ObservedObject private var permissions = PermissionManager.shared

    // Provider
    @AppStorage("sttProvider") private var sttProvider = STTProviderType.groq.rawValue
    @AppStorage("groqApiKey") private var groqApiKey = ""
    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @AppStorage("deepgramApiKey") private var deepgramApiKey = ""

    // Language
    @AppStorage("sttLanguage") private var sttLanguage = STTLanguage.auto.rawValue

    // Behavior
    @AppStorage("outputMode") private var outputMode = OutputMode.pasteOnly.rawValue
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("recordingMode") private var recordingMode = RecordingMode.holdToTalk.rawValue
    @AppStorage("noiseSuppression") private var noiseSuppression = true
    @AppStorage("preferredInputDeviceID") private var preferredInputDeviceID = ""
    @State private var pushToTalkTrigger = PushToTalkTrigger.loadFromDefaults()

    private var selectedProvider: STTProviderType {
        STTProviderType(rawValue: sttProvider) ?? .groq
    }

    private var inputDevices: [AudioRecorder.InputDevice] {
        recorder.availableInputDevices()
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            providerTab
                .tabItem { Label("Provider", systemImage: "cloud") }

            recordingTab
                .tabItem { Label("Recording", systemImage: "mic") }

            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            // Fallback if saved device no longer exists
            if preferredInputDeviceID.isEmpty || !inputDevices.contains(where: { $0.id == preferredInputDeviceID }) {
                preferredInputDeviceID = inputDevices.first?.id ?? ""
            }
            recorder.selectedInputID = preferredInputDeviceID.isEmpty ? nil : preferredInputDeviceID
            permissions.refresh()
            migrateLegacyOutputSettingIfNeeded()
            pushToTalkTrigger = PushToTalkTrigger.loadFromDefaults()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    permissionCard(
                        title: "Microphone",
                        detail: "Required to record your voice.",
                        status: permissions.microphoneStatus,
                        actionTitle: permissions.microphoneStatus == .granted ? "Refresh" : "Request Access"
                    ) {
                        if permissions.microphoneStatus == .granted {
                            permissions.refresh()
                        } else {
                            permissions.requestMicrophoneAccess()
                        }
                    }

                    permissionCard(
                        title: "Accessibility",
                        detail: "Needed for pasting text into the active app.",
                        status: permissions.accessibilityStatus,
                        actionTitle: permissions.accessibilityStatus == .granted ? "Refresh" : "Request Access"
                    ) {
                        if permissions.accessibilityStatus == .granted {
                            permissions.refresh()
                        } else {
                            permissions.requestAccessibilityAccess()
                        }
                    }

                    permissionCard(
                        title: "Input Monitoring",
                        detail: "Required for global push-to-talk shortcuts like Option or Command.",
                        status: permissions.inputMonitoringStatus,
                        actionTitle: permissions.inputMonitoringStatus == .granted ? "Refresh" : "Open Settings"
                    ) {
                        if permissions.inputMonitoringStatus == .granted {
                            permissions.refresh()
                        } else {
                            permissions.openInputMonitoringSettings()
                        }
                    }
                }
            }

            Section("Output") {
                Picker("Output Mode", selection: $outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .onChange(of: outputMode) { _, newValue in
                    autoPaste = (newValue != OutputMode.copyOnly.rawValue)
                    if newValue != OutputMode.copyOnly.rawValue {
                        TextInserter.requestAccessibilityIfNeeded()
                    }
                }

                outputModeSummary
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

    // MARK: - Recording Tab

    private var recordingTab: some View {
        Form {
            Section("Mode") {
                Picker("Recording Mode", selection: $recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text((RecordingMode(rawValue: recordingMode) ?? .holdToTalk).description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio Input") {
                Picker("Microphone", selection: $preferredInputDeviceID) {
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: preferredInputDeviceID) { _, newValue in
                    recorder.selectedInputID = newValue.isEmpty ? nil : newValue
                }

                Toggle("Noise suppression", isOn: $noiseSuppression)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Input level")
                        Spacer()
                        Text(state.isMicTestRunning ? "Testing…" : "Live")
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: Double(state.audioLevel), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(state.audioLevel > 0.8 ? .red : .accentColor)

                    Button(state.isMicTestRunning ? "Testing microphone…" : "Test Microphone") {
                        PipelineController.shared.startMicTest()
                    }
                    .disabled(state.isMicTestRunning || state.isRecording)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Hotkey Tab

    private var hotkeyTab: some View {
        Form {
            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Push to talk")
                        .font(.headline)

                    TriggerRecorderField(trigger: $pushToTalkTrigger)
                        .onChange(of: pushToTalkTrigger) { _, _ in
                            HotkeyManager.shared.setup()
                        }

                    HStack {
                        Button("Use Command") {
                            pushToTalkTrigger = .modifier(.command)
                            PushToTalkTrigger.saveToDefaults(pushToTalkTrigger)
                            HotkeyManager.shared.setup()
                        }
                        .controlSize(.small)

                        Button("Use Option") {
                            pushToTalkTrigger = .modifier(.option)
                            PushToTalkTrigger.saveToDefaults(pushToTalkTrigger)
                            HotkeyManager.shared.setup()
                        }
                        .controlSize(.small)

                        Spacer()

                        Button("Reset to Default") {
                            pushToTalkTrigger = .defaultValue
                            PushToTalkTrigger.saveToDefaults(pushToTalkTrigger)
                            HotkeyManager.shared.setup()
                        }
                        .controlSize(.small)
                    }

                    if permissions.inputMonitoringStatus != .granted {
                        Label("Input Monitoring must be enabled for push-to-talk to work outside the app.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text(hotkeyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotkeyHint: String {
        let mode = RecordingMode(rawValue: recordingMode) ?? .holdToTalk
        switch mode {
        case .holdToTalk:
            return "Hold to record, release to transcribe and paste"
        case .toggle:
            return "Press once to start recording, press again to stop and transcribe"
        }
    }

    private var outputModeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                currentOutputMode.description,
                systemImage: currentOutputMode == .copyOnly ? "doc.on.doc" : "arrow.right.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if currentOutputMode == .pasteAndSubmit {
                Label("Best for chat boxes and prompts that submit on Enter.", systemImage: "paperplane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentOutputMode != .copyOnly && permissions.accessibilityStatus != .granted {
                Label("Accessibility permission is needed for paste actions.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var currentOutputMode: OutputMode {
        OutputMode(rawValue: outputMode) ?? .pasteOnly
    }

    @ViewBuilder
    private func permissionCard(title: String, detail: String, status: PermissionManager.Status, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbolName)
                .foregroundStyle(statusColor(for: status))
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .fontWeight(.medium)
                    Spacer()
                    Text(status.rawValue)
                        .font(.caption)
                        .foregroundStyle(statusColor(for: status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor(for: status).opacity(0.12), in: Capsule())
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusColor(for status: PermissionManager.Status) -> Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private func migrateLegacyOutputSettingIfNeeded() {
        if UserDefaults.standard.string(forKey: "outputMode") == nil {
            outputMode = autoPaste ? OutputMode.pasteOnly.rawValue : OutputMode.copyOnly.rawValue
        }
    }
}
