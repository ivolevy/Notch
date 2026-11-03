import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DynamicNotchView: View {
    @ObservedObject var stateModel: NotchStateModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var cameraService: CameraMirrorService

    private let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)

    var body: some View {
        let shape = DynamicNotchShape(
            bottomCornerRadius: stateModel.bottomCornerRadius,
            topShoulderRadius: 6
        )

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Pure Black (#000000) hardware-like Notch background
                Color.black

                if stateModel.expansionState == .idle {
                    idleCapsuleContent
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(springAnimation) {
                                stateModel.isManuallyCollapsed = false
                                stateModel.isHovering = true
                            }
                        }
                        .transition(.opacity)
                } else {
                    expandedNotchContent
                        .transition(.opacity)
                }
            }
            .frame(
                width: stateModel.targetWidth,
                height: stateModel.targetHeight
            )
            // Strict clipping inside the notch silhouette so nothing can ever overflow
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    (stateModel.isDraggingOverLeftShelf || stateModel.isDraggingOverRightAirDrop)
                        ? Color.cyan.opacity(0.65)
                        : Color.white.opacity(stateModel.expansionState == .idle ? 0.07 : 0.11),
                    lineWidth: (stateModel.isDraggingOverLeftShelf || stateModel.isDraggingOverRightAirDrop) ? 1.2 : 0.6
                )
            )
            .contextMenu {
                Button(stateModel.isPinnedOpen ? "Desanclar Notch" : "Anclar Notch") {
                    withAnimation(springAnimation) {
                        stateModel.isPinnedOpen.toggle()
                    }
                }
                Divider()
                Button("Cerrar Notch") {
                    NSApp.terminate(nil)
                }
            }
            .animation(springAnimation, value: stateModel.expansionState)
            .animation(springAnimation, value: stateModel.activeTab)
            .animation(springAnimation, value: stateModel.targetWidth)
            .animation(springAnimation, value: stateModel.targetHeight)
            .animation(springAnimation, value: stateModel.isDraggingOverLeftShelf)
            .animation(springAnimation, value: stateModel.isDraggingOverRightAirDrop)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Idle State (Minimalist Apple Dynamic Island Pill: 176x32 px)
    private var idleCapsuleContent: some View {
        HStack(spacing: 8) {
            // Left: Mini album cover or subtle music glyph
            if let art = nowPlaying.artworkImage {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(nowPlaying.isPlaying ? .green : .white.opacity(0.28))
            }

            Spacer(minLength: 4)

            // Center: Hardware camera lens aesthetic
            Circle()
                .fill(Color(red: 0.06, green: 0.07, blue: 0.11))
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .fill(Color.blue.opacity(0.28))
                        .frame(width: 3.5, height: 3.5)
                )

            Spacer(minLength: 4)

            // Right: Privacy / status dot (Apple style)
            HStack(spacing: 4) {
                if stateModel.hasShelfItems {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 5.5, height: 5.5)
                } else if cameraService.isCameraActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5.5, height: 5.5)
                } else if stateModel.isRingLightOn {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 5.5, height: 5.5)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Expanded Contextual State (Left-Aligned Menu Bar + Active Module Only)
    private var expandedNotchContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Minimalist Apple Segmented Switcher (Left) + Pin / Unpin Controls (Right)
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    segmentedTabPill(tab: .music, icon: "play.circle.fill")
                    segmentedTabPill(tab: .tray, icon: "tray.and.arrow.down")
                    segmentedTabPill(tab: .camera, icon: "video")
                }
                .padding(2.5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())

                Spacer(minLength: 0)

                // Pin / Unpin Button Section
                pinControlsSection
            }

            // Active Contextual Module
            Group {
                switch stateModel.activeTab {
                case .music:
                    NowPlayingModuleView(service: nowPlaying, stateModel: stateModel)
                case .tray:
                    DropTrayModuleView(stateModel: stateModel)
                case .camera:
                    MirrorLightModuleView(
                        cameraService: cameraService,
                        stateModel: stateModel
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(
                height: stateModel.activeTab == .camera
                    ? 68
                    : (stateModel.activeTab == .tray ? stateModel.trayModuleHeight : 52)
            )

            if let banner = stateModel.statusBanner {
                Text(banner)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(stateModel.statusIsError ? Color.red.opacity(0.9) : Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if stateModel.isPinnedOpen {
                    withAnimation(springAnimation) {
                        stateModel.showUnpinButton.toggle()
                    }
                }
            }
        )
    }

    // MARK: - Pin / Unpin Controls
    @ViewBuilder
    private var pinControlsSection: some View {
        if stateModel.isPinnedOpen {
            if stateModel.showUnpinButton {
                Button(action: {
                    withAnimation(springAnimation) {
                        stateModel.isPinnedOpen = false
                        stateModel.showUnpinButton = false
                        stateModel.isHovering = false
                    }
                }) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "pin.slash.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Desanclar")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .help("Desanclar Notch")
            } else {
                Button(action: {
                    withAnimation(springAnimation) {
                        stateModel.showUnpinButton = true
                    }
                }) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Anclado")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Color.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.cyan.opacity(0.18))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(springAnimation) {
                            stateModel.showUnpinButton = true
                        }
                    }
                )
                .help("Doble clic para desanclar")
            }
        } else {
            Button(action: {
                withAnimation(springAnimation) {
                    stateModel.isPinnedOpen = true
                    stateModel.showUnpinButton = false
                }
            }) {
                HStack(spacing: 3.5) {
                    Image(systemName: "pin")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Anclar")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundColor(Color.white.opacity(0.68))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Anclar Notch (mantener abierto)")
        }
    }

    private func segmentedTabPill(tab: NotchTab, icon: String) -> some View {
        let isSelected = (stateModel.activeTab == tab)
        return Button(action: {
            withAnimation(springAnimation) {
                stateModel.activeTab = tab
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.68))
                .frame(width: 24, height: 20)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(
            ActiveHoverTrackingView(
                onHover: { hovering in
                    if hovering {
                        stateModel.switchTabOnHover(tab)
                    }
                },
                onClick: {
                    withAnimation(springAnimation) {
                        stateModel.activeTab = tab
                    }
                }
            )
        )
    }
}

/// An NSViewRepresentable with an activeAlways tracking area so hover events
/// fire immediately on macOS panels without requiring an initial click or window activation.
struct ActiveHoverTrackingView: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ActiveTrackingNSView {
        let view = ActiveTrackingNSView()
        view.onHover = onHover
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ActiveTrackingNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onClick = onClick
    }
}

final class ActiveTrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onHover?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onHover?(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onClick?()
        }
        super.mouseDown(with: event)
    }
}
