import SwiftUI

struct ContentView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Transcription list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if state.transcriptions.isEmpty {
                                VStack(spacing: 12) {
                                    Spacer(minLength: 60)
                                    Image(systemName: "waveform.circle")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                    Text("Hold your shortcut and speak")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text("Your transcriptions will appear here")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            ForEach(state.transcriptions) { entry in
                                TranscriptionRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: state.transcriptions.count) {
                        if let first = state.transcriptions.first {
                            withAnimation {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }

                Divider()

                // Status bar
                StatusBar(state: state)
            }

            if state.showRecordingOverlay || state.isRecording {
                RecordingOverlay(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.showRecordingOverlay)
        .frame(minWidth: 300, minHeight: 200)
    }
}

// MARK: - Transcription Row

struct TranscriptionRow: View {
    let entry: Transcription
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.text)
                .font(.system(.body, design: .rounded))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.isRecording {
                // Recording indicator
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)

                // Mini waveform
                HStack(spacing: 1.5) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.red.opacity(0.8))
                            .frame(width: 3, height: barHeight(index: i))
                    }
                }
                .frame(height: 16)
                .animation(.easeInOut(duration: 0.1), value: state.audioLevel)

                Text(formatDuration(state.recordingDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)

            } else if state.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)

            } else {
                Image(systemName: "waveform.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Hold your shortcut to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func barHeight(index: Int) -> CGFloat {
        let level = CGFloat(state.audioLevel)
        let variation = sin(Double(index) * 0.9) * 0.3 + 0.7
        return max(3, level * 16 * CGFloat(variation))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct RecordingOverlay: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 78, height: 78)

                    Image(systemName: state.isRecording ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(state.isRecording ? .red : .secondary)
                }

                Text("Listening…")
                    .font(.headline)
                    .fontWeight(.semibold)

                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.9))
                            .frame(width: 4, height: overlayBarHeight(index: i))
                    }
                }
                .frame(height: 28)
                .animation(.easeInOut(duration: 0.08), value: state.audioLevel)

                Text("Release the shortcut to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 18)
        }
    }

    private func overlayBarHeight(index: Int) -> CGFloat {
        let level = CGFloat(max(state.audioLevel, 0.05))
        let variation = sin(Double(index) * 0.75) * 0.28 + 0.72
        return max(6, level * 28 * CGFloat(variation))
    }
}
