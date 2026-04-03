import SwiftUI
import AVFoundation
import ApplicationServices

struct SettingsView: View {
    @AppStorage("openaiApiKey") private var apiKey = ""
    @AppStorage("transcriptionMode") private var modeRaw = TranscriptionMode.normal.rawValue
    @State private var micPermission = false
    @State private var axPermission = false
    @State private var inputMonitoring = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            usageTab.tabItem { Label("Usage", systemImage: "chart.bar") }
        }
        .frame(width: 480, height: 380)
        .onAppear { refreshPermissions() }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("OpenAI API Key") {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Uses gpt-4o-transcribe — best for Vietnamese + English")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription Mode") {
                Picker("Mode", selection: $modeRaw) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(currentMode.description)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                HStack {
                    Text("Push-to-talk")
                    Spacer()
                    Text("⌘ Command")
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                Text("Hold to record, release to transcribe")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                permissionRow("Microphone", granted: micPermission) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { refreshPermissions() }
                    }
                }
                permissionRow("Accessibility", granted: axPermission) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    refreshPermissions()
                }
                permissionRow("Input Monitoring", granted: inputMonitoring) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Usage Tab

    private var usageTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(UsageTracker.currentMonthCount)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("transcriptions this month")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                }
            }

            Section("History") {
                let stats = UsageTracker.stats
                if stats.isEmpty {
                    Text("No usage data yet").foregroundStyle(.secondary)
                } else {
                    ForEach(stats, id: \.month) { item in
                        HStack {
                            Text(item.month).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("\(item.count) transcriptions")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    private var currentMode: TranscriptionMode {
        TranscriptionMode(rawValue: modeRaw) ?? .normal
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            if !granted {
                Button("Grant") { action() }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Text("Granted").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    private func refreshPermissions() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axPermission = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
    }
}
