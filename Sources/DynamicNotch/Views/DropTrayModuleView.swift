import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Native AppKit view for each stored image in the Left Shelf:
/// - Hovering (`mouseEntered` / `mouseExited`): shows the small delete 'x' button at top-right.
/// - Dragging (`mouseDragged`): drags the file (or transparent PNG) out to Finder / Desktop / any app.
/// - Clicking (`mouseUp` on main area): removes background and downloads transparent PNG to ~/Downloads.
/// - Clicking on 'x' (top-right 16x16 px) or right-clicking: deletes the image from the shelf.
final class DraggableAndClickableFileNSView: NSView, NSDraggingSource {
    var fileURL: URL?
    var previewImage: NSImage?
    var onHoverChanged: ((Bool) -> Void)?
    var onCloseHoverChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDeleteClick: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var didStartDrag: Bool = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { return true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        onCloseHoverChanged?(false)
    }

    private func isPointInCloseButton(_ pt: NSPoint) -> Bool {
        // Close button hit area: top right 16x16 px
        let closeRect = NSRect(x: bounds.width - 16, y: 0, width: 16, height: 16)
        return closeRect.contains(pt)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        onCloseHoverChanged?(isPointInCloseButton(pt))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        self.window?.makeKey()
        let pt = convert(event.locationInWindow, from: nil)
        if isPointInCloseButton(pt) {
            onDeleteClick?()
            return
        }
        mouseDownPoint = pt
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL = fileURL else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        if let start = mouseDownPoint {
            let dx = currentPoint.x - start.x
            let dy = currentPoint.y - start.y
            if hypot(dx, dy) < 4.0 { return }
        }
        mouseDownPoint = nil
        didStartDrag = true

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = previewImage ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        let dragSize = NSSize(width: 44, height: 44)
        let renderedThumb = NSImage(size: dragSize)
        renderedThumb.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: dragSize), from: .zero, operation: .sourceOver, fraction: 0.94)
        renderedThumb.unlockFocus()

        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: dragSize), contents: renderedThumb)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag, let startPt = mouseDownPoint {
            let currentPoint = convert(event.locationInWindow, from: nil)
            if !isPointInCloseButton(startPt) && !isPointInCloseButton(currentPoint) {
                onClick?()
            }
        }
        mouseDownPoint = nil
        didStartDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

struct DraggableShelfItemOverlay: NSViewRepresentable {
    let fileURL: URL?
    let previewImage: NSImage?
    let onHoverChanged: (Bool) -> Void
    let onCloseHoverChanged: (Bool) -> Void
    let onClick: () -> Void
    let onRightClick: () -> Void
    let onDeleteClick: () -> Void

    func makeNSView(context: Context) -> DraggableAndClickableFileNSView {
        let view = DraggableAndClickableFileNSView()
        view.fileURL = fileURL
        view.previewImage = previewImage
        view.onHoverChanged = onHoverChanged
        view.onCloseHoverChanged = onCloseHoverChanged
        view.onClick = onClick
        view.onRightClick = onRightClick
        view.onDeleteClick = onDeleteClick
        return view
    }

    func updateNSView(_ nsView: DraggableAndClickableFileNSView, context: Context) {
        nsView.fileURL = fileURL
        nsView.previewImage = previewImage
        nsView.onHoverChanged = onHoverChanged
        nsView.onCloseHoverChanged = onCloseHoverChanged
        nsView.onClick = onClick
        nsView.onRightClick = onRightClick
        nsView.onDeleteClick = onDeleteClick
    }
}

struct ShelfThumbnailCellView: View {
    let item: ShelfImageItem
    @ObservedObject var stateModel: NotchStateModel
    @State private var isHovered: Bool = false
    @State private var isCloseHovered: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main Thumbnail Body
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.08))
                    .frame(width: 40, height: 40)

                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                item.isTransparentPNG ? Color.green.opacity(0.85) : Color.white.opacity(0.18),
                                lineWidth: item.isTransparentPNG ? 1.2 : 0.6
                            )
                    )

                if item.isProcessing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 40, height: 40)

                        ProgressView()
                            .scaleEffect(0.5)
                    }
                } else if item.isTransparentPNG {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 11, height: 11)
                        .overlay(
                            Image(systemName: "arrow.down")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundColor(.black)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 40, height: 40)

            // Small Delete 'x' Button at Top-Right on Hover (Sleek Apple Monochrome)
            if isHovered && !item.isProcessing {
                Circle()
                    .fill(isCloseHovered ? Color.white.opacity(0.35) : Color.black.opacity(0.82))
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isCloseHovered ? 0.65 : 0.35), lineWidth: 0.7)
                    )
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .padding([.top, .trailing], 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 40, height: 40)
        .overlay(
            DraggableShelfItemOverlay(
                fileURL: item.activeURL,
                previewImage: item.thumbnail,
                onHoverChanged: { hovering in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        self.isHovered = hovering
                        if !hovering {
                            self.isCloseHovered = false
                        }
                    }
                },
                onCloseHoverChanged: { closeHovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        self.isCloseHovered = closeHovering
                    }
                },
                onClick: {
                    if item.isTransparentPNG {
                        NSWorkspace.shared.activateFileViewerSelecting([item.activeURL])
                        stateModel.showTemporaryStatus("Mostrando en Descargas: \(item.activeURL.lastPathComponent)", isError: false)
                    } else {
                        stateModel.removeBackgroundForItem(id: item.id)
                    }
                },
                onRightClick: {
                    stateModel.removeShelfItem(id: item.id)
                },
                onDeleteClick: {
                    stateModel.removeShelfItem(id: item.id)
                }
            )
        )
        .help(item.isTransparentPNG ? "Clic: ver en Descargas · Arrastrar: mover archivo · 'x': borrar" : "Clic: quitar fondo y guardar en Descargas · Arrastrar: mover archivo · 'x': borrar")
    }
}

struct DropTrayModuleView: View {
    @ObservedObject var stateModel: NotchStateModel

    private let threeColumnGrid: [GridItem] = [
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6)
    ]

    var body: some View {
        HStack(spacing: 10) {
            // LEFT SIDE: Multi-image shelf in rows of 3 (drag to store, drag out to move, click to remove background & download PNG)
            leftShelfZone
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // RIGHT SIDE: AirDrop drop zone
            rightAirDropZone
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: stateModel.trayModuleHeight)
    }

    // MARK: - Left Zone: Multi-Image Shelf in Rows of 3 (Solo Logos, Bordes Lisos)
    private var leftShelfZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    stateModel.isDraggingOverLeftShelf
                        ? Color.cyan.opacity(0.18)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            stateModel.isDraggingOverLeftShelf
                                ? Color.cyan.opacity(0.85)
                                : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                )

            if stateModel.hasShelfItems {
                HStack(alignment: .top, spacing: 6) {
                    // Vertical Scrollable Grid of Stored Images in Rows of 3
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: threeColumnGrid, alignment: .leading, spacing: 6) {
                            ForEach(stateModel.shelfItems) { item in
                                ShelfThumbnailCellView(item: item, stateModel: stateModel)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                    }

                    // Minimalist Clear-All Button anchored at top-right of the shelf
                    Button(action: {
                        stateModel.clearAllShelfItems()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                    .padding(.trailing, 7)
                    .help("Vaciar todas las imágenes")
                }
            } else {
                // Empty Left Shelf: Logo only, smooth surface
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(stateModel.isDraggingOverLeftShelf ? .cyan : .white.opacity(0.75))
            }
        }
    }

    // MARK: - Right Zone: AirDrop (Solo Logo, Bordes Lisos, Envío Directo al Soltar)
    private var rightAirDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    stateModel.isDraggingOverRightAirDrop
                        ? Color.cyan.opacity(0.18)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            stateModel.isDraggingOverRightAirDrop
                                ? Color.cyan.opacity(0.85)
                                : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                )

            Image(systemName: "airplayaudio")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(stateModel.isDraggingOverRightAirDrop ? .cyan : .cyan.opacity(0.85))
        }
    }
}
