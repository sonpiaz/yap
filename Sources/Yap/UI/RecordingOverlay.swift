import SwiftUI

/// Floating overlay window that shows waveform during recording
class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?

    private init() {}

    func show() {
        guard window == nil else { return }

        let overlayView = RecordingOverlayView()
        let hosting = NSHostingView(rootView: overlayView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 100
            let y = screenFrame.minY + 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
        self.hostingView = hosting
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }
}

struct RecordingOverlayView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(appState.isRecording ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: appState.isRecording)

            // Mini waveform
            HStack(spacing: 1.5) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: miniBarHeight(index: i))
                }
            }
            .frame(height: 24)

            // Duration
            Text(formatDuration(appState.recordingDuration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func miniBarHeight(index: Int) -> CGFloat {
        let level = CGFloat(appState.audioLevel)
        let variation = sin(Double(index) * 0.8) * 0.3 + 0.7
        return max(3, level * 24 * CGFloat(variation))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
