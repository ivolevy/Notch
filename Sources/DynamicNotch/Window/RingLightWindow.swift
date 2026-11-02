import AppKit
import SwiftUI

/// Full-screen click-through Ring Light ("Aro de Luz") window for video calls
final class RingLightWindowController {
    static let shared = RingLightWindowController()

    private var ringPanel: NSPanel?

    private init() {}

    func updateRingLight(isEnabled: Bool, warmth: Double) {
        if isEnabled {
            showRingLight(warmth: warmth)
        } else {
            hideRingLight()
        }
    }

    private func showRingLight(warmth: Double) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        if ringPanel == nil {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            self.ringPanel = panel
        }

        guard let panel = ringPanel else { return }
        panel.setFrame(screen.frame, display: true)
        panel.contentView = NSHostingView(rootView: RingLightOverlayView(warmth: warmth))
        panel.orderFrontRegardless()
    }

    private func hideRingLight() {
        ringPanel?.orderOut(nil)
    }
}

struct RingLightOverlayView: View {
    let warmth: Double

    private var lightColor: Color {
        // Interpolate between crisp studio white and warm golden white
        let red = 1.0
        let green = 1.0 - (warmth * 0.10)
        let blue = 1.0 - (warmth * 0.28)
        return Color(red: red, green: green, blue: blue)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                lightColor.opacity(0.96),
                                Color.white.opacity(0.92),
                                lightColor.opacity(0.96)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 38
                    )
                    .shadow(color: lightColor.opacity(0.85), radius: 36, x: 0, y: 0)
                    .shadow(color: Color.white.opacity(0.65), radius: 64, x: 0, y: 0)
                    .padding(14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .edgesIgnoringSafeArea(.all)
    }
}
