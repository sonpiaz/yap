import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Spacer()
                Text("v0.1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Recording indicator
            if appState.isRecording {
                RecordingIndicator(audioLevel: appState.audioLevel)
                    .frame(height: 40)
                Divider()
            }

            // Last transcription
            if !appState.lastTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastTranscription)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Divider()
            }

            // Mode selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(TranscriptionMode.allCases) { mode in
                    Button {
                        appState.setMode(mode)
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                                .frame(width: 20)
                            Text(mode.rawValue)
                            Spacer()
                            if appState.currentMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Stats
            HStack {
                Label("\(appState.totalTranscriptions)", systemImage: "text.bubble")
                Spacer()
                Label("\(appState.totalWordsToday) words", systemImage: "character.cursor.ibeam")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            // Actions
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")

            Button("Quit Yap") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .orange }
        if appState.isModelLoaded { return .green }
        return .gray
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        if appState.isTranscribing { return "Transcribing..." }
        if appState.isModelLoaded { return "Ready — hold ⌥R to speak" }
        return "Loading model..."
    }
}

struct RecordingIndicator: View {
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(index: i))
                    .frame(width: 6, height: barHeight(index: i))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }

    private func barHeight(index: Int) -> CGFloat {
        let normalized = CGFloat(audioLevel)
        let position = CGFloat(index) / 20.0
        let distance = abs(position - 0.5) * 2
        let height = max(4, (1 - distance) * normalized * 36)
        return height
    }

    private func barColor(index: Int) -> Color {
        let normalized = CGFloat(audioLevel)
        if normalized > 0.7 { return .red }
        if normalized > 0.4 { return .orange }
        return .green
    }
}
