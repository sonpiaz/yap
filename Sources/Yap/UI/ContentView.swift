import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Transcription list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if state.transcriptions.isEmpty {
                                emptyState
                            }
                            ForEach(state.transcriptions) { entry in
                                TranscriptionRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                }

                Divider()
                statusBar
            }

            // Recording overlay
            if state.showOverlay {
                recordingOverlay
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Hold ⌘ Command and speak")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your transcriptions will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if state.isRecording {
                Circle().fill(.red).frame(width: 8, height: 8)
                levelBars
                Text(formatDuration(state.recordingDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            } else if state.isTranscribing {
                ProgressView().controlSize(.small)
                Text("Transcribing...").font(.caption).foregroundStyle(.secondary)
            } else if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
            } else {
                Image(systemName: "waveform.circle")
                    .foregroundStyle(.secondary).font(.caption)
                Text("Hold ⌘ to record").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gear").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Level Bars

    private var levelBars: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red.opacity(0.8))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.1), value: state.audioLevel)
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.28)).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 78, height: 78)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.red)
                }
                Text("Listening…")
                    .font(.headline).fontWeight(.semibold)

                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.9))
                            .frame(width: 4, height: overlayBarHeight(i))
                    }
                }
                .frame(height: 28)
                .animation(.easeInOut(duration: 0.08), value: state.audioLevel)

                Text("Release ⌘ to stop")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 18)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Helpers

    private func barHeight(_ i: Int) -> CGFloat {
        let level = CGFloat(state.audioLevel)
        let variation = sin(Double(i) * 0.9) * 0.3 + 0.7
        return max(3, level * 16 * variation)
    }

    private func overlayBarHeight(_ i: Int) -> CGFloat {
        let level = CGFloat(max(state.audioLevel, 0.05))
        let variation = sin(Double(i) * 0.75) * 0.28 + 0.72
        return max(6, level * 28 * variation)
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                Text(entry.timestamp, style: .time)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
    }
}
