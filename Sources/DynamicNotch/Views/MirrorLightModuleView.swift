import SwiftUI

struct MirrorLightModuleView: View {
    @ObservedObject var cameraService: CameraMirrorService
    @ObservedObject var stateModel: NotchStateModel
    @State private var isCameraHovered: Bool = false

    private let mirrorSize: CGFloat = 50

    var body: some View {
        HStack(spacing: 14) {
            // Circular Live Webcam Mirror
            ZStack {
                WebcamCircularPreview(session: cameraService.captureSession)
                    .frame(width: mirrorSize, height: mirrorSize)
                    .clipShape(Circle())
                    .opacity(cameraService.isCameraActive ? 1.0 : 0.25)

                if !cameraService.isCameraActive {
                    Image(systemName: "video.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }

                Circle()
                    .strokeBorder(
                        cameraService.isCameraActive
                            ? (stateModel.isRingLightOn ? Color.yellow.opacity(0.9) : Color.green.opacity(0.85))
                            : Color.white.opacity(0.22),
                        lineWidth: isCameraHovered ? 2.5 : 1.8
                    )
                    .frame(width: mirrorSize, height: mirrorSize)
            }
            .scaleEffect(isCameraHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isCameraHovered)
            .contentShape(Circle())
            .overlay(
                ActiveHoverTrackingView(
                    onHover: { hovering in
                        self.isCameraHovered = hovering
                    },
                    onClick: {
                        cameraService.toggleCamera()
                    }
                )
            )
            .help(cameraService.isCameraActive ? "Pausar espejo" : "Activar espejo")

            // Status & Quick hint
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(cameraService.isCameraActive ? Color.green : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)

                    Text(cameraService.statusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Text(stateModel.isRingLightOn ? "Aro de luz activo" : (cameraService.isCameraActive ? "Toca para pausar" : "Toca para activar"))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Minimalist Ring Light Controls
            HStack(spacing: 6) {
                if stateModel.isRingLightOn {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            stateModel.ringLightWarmth = stateModel.ringLightWarmth < 0.5 ? 0.85 : 0.15
                        }
                    }) {
                        Circle()
                            .fill(
                                stateModel.ringLightWarmth > 0.5
                                    ? Color(red: 1.0, green: 0.78, blue: 0.35)
                                    : Color.white
                            )
                            .frame(width: 14, height: 14)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(stateModel.ringLightWarmth > 0.5 ? "Cambiar a luz fría" : "Cambiar a luz cálida")
                    .transition(.scale.combined(with: .opacity))
                }

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        stateModel.isRingLightOn.toggle()
                    }
                }) {
                    Image(systemName: stateModel.isRingLightOn ? "sun.max.fill" : "sun.max")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(stateModel.isRingLightOn ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(
                            stateModel.isRingLightOn
                                ? Color(red: 1.0, green: 0.92, blue: 0.65)
                                : Color.white.opacity(0.12)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Activar / Desactivar Aro de Luz")
            }
        }
        .onAppear {
            cameraService.startCamera()
        }
        .onDisappear {
            cameraService.stopCamera()
        }
    }
}
