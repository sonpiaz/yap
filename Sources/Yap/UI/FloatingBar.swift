import SwiftUI
import AppKit

/// Floating voice indicator — pure visual, no text.
/// Design philosophy: a living, breathing ember of sound.
/// Inspired by: analog VU meters, luxury brand minimalism, organic motion.
class FloatingBarController {
    static let shared = FloatingBarController()

    private var window: NSWindow?
    private var hostingView: NSView?

    private init() {}

    func show() {
        guard window == nil else { return }

        let view = FloatingBarView()
            .environmentObject(AppState.shared)
        let hosting = NSHostingView(rootView: view)

        let size = NSSize(width: 64, height: 64)
        hosting.frame = NSRect(origin: .zero, size: size)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = false
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = false

        // Position: top-center, tucked under menu bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.maxY - 12
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.animationBehavior = .none
        win.orderFront(nil)
        window = win
        hostingView = hosting
    }

    func hide() {
        guard let win = window else { return }
        win.orderOut(nil)

        let hosting = hostingView
        window = nil
        hostingView = nil
        DispatchQueue.main.async {
            win.contentView = nil
            _ = hosting
        }
    }
}

// MARK: - The Visual — A Living Sound Orb

struct FloatingBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var phase: Double = 0
    @State private var breathe: Double = 0

    // Smooth the audio level for organic motion
    private var smoothLevel: CGFloat {
        CGFloat(max(state.audioLevel, 0.05))
    }

    var body: some View {
        ZStack {
            // Layer 1: Outer glow — soft red aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.red.opacity(0.3 * Double(smoothLevel) + 0.05),
                            Color.red.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 32
                    )
                )
                .frame(width: 56, height: 56)
                .scaleEffect(1.0 + smoothLevel * 0.4 + breathe * 0.08)

            // Layer 2: Waveform ring — the voice visualizer
            WaveformRing(
                level: smoothLevel,
                phase: phase
            )
            .fill(
                AngularGradient(
                    colors: [
                        Color.red.opacity(0.85),
                        Color(red: 1.0, green: 0.35, blue: 0.25).opacity(0.6),
                        Color.red.opacity(0.85),
                    ],
                    center: .center
                )
            )
            .frame(width: 36, height: 36)

            // Layer 3: Core — the red ember
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.25, blue: 0.2),   // warm red center
                            Color(red: 0.85, green: 0.1, blue: 0.15),  // deep crimson edge
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 14, height: 14)
                .shadow(color: Color.red.opacity(0.6), radius: 6)
                .shadow(color: Color.red.opacity(0.3), radius: 12)
                .scaleEffect(1.0 + smoothLevel * 0.15)
        }
        .frame(width: 64, height: 64)
        .animation(.easeOut(duration: 0.08), value: smoothLevel)
        .animation(.easeInOut(duration: 2.0), value: breathe)
        .onAppear {
            // Continuous waveform rotation
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                DispatchQueue.main.async {
                    phase += 0.06
                }
            }
            // Slow breathing rhythm
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = 1.0
            }
        }
    }
}

// MARK: - Waveform Ring — Organic Voice Visualizer

/// A circular ring of bars that dance with audio level.
/// Each bar has slightly different frequency response — creates organic, alive motion.
struct WaveformRing: Shape {
    var level: CGFloat
    var phase: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(level, phase) }
        set {
            level = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius: CGFloat = min(rect.width, rect.height) / 2 - 2
        let barCount = 24
        let barWidth: CGFloat = 2.2

        for i in 0..<barCount {
            let angle = (Double(i) / Double(barCount)) * 2.0 * .pi - .pi / 2

            // Each bar responds differently — creates texture
            let freq1 = sin(phase + Double(i) * 0.55) * 0.5 + 0.5
            let freq2 = cos(phase * 0.7 + Double(i) * 0.35) * 0.3 + 0.5
            let response = (freq1 * 0.6 + freq2 * 0.4)

            // Bar height based on audio level × individual response
            let maxExtension: CGFloat = 8
            let extension_ = maxExtension * level * CGFloat(response)
            let minBar: CGFloat = 1.5

            let innerR = baseRadius - minBar
            let outerR = baseRadius + extension_

            let cosA = CGFloat(cos(angle))
            let sinA = CGFloat(sin(angle))

            let inner = CGPoint(
                x: center.x + innerR * cosA,
                y: center.y + innerR * sinA
            )
            let outer = CGPoint(
                x: center.x + outerR * cosA,
                y: center.y + outerR * sinA
            )

            // Draw rounded bar
            let perpX = -sinA * barWidth / 2
            let perpY = cosA * barWidth / 2

            path.move(to: CGPoint(x: inner.x + perpX, y: inner.y + perpY))
            path.addLine(to: CGPoint(x: outer.x + perpX, y: outer.y + perpY))
            path.addLine(to: CGPoint(x: outer.x - perpX, y: outer.y - perpY))
            path.addLine(to: CGPoint(x: inner.x - perpX, y: inner.y - perpY))
            path.closeSubpath()
        }

        return path
    }
}


