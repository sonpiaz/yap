import SwiftUI
import AppKit

/// A small floating bar that appears at the top-center of screen during recording.
/// Minimal, non-intrusive — like Wispr Flow but simpler.
class FloatingBarController {
    static let shared = FloatingBarController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<FloatingBarView>?

    private init() {}

    func show() {
        guard window == nil else { return }

        let view = FloatingBarView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 44)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position: top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.maxY - 60
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFront(nil)
        window = win
        hostingView = hosting
    }

    func hide() {
        window?.close()
        window = nil
        hostingView = nil
    }
}

struct FloatingBarView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.6), radius: 4)

            // Waveform
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: barHeight(i))
                }
            }
            .frame(height: 20)
            .animation(.easeInOut(duration: 0.08), value: state.audioLevel)

            // Timer
            Text(formatTime(state.recordingDuration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text("Release ⌘")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        )
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let level = CGFloat(max(state.audioLevel, 0.08))
        let variation = sin(Double(i) * 0.9) * 0.3 + 0.7
        return max(3, level * 20 * variation)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
