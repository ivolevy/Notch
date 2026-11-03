import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Custom non-activating borderless floating NSPanel pinned to the top edge of NSScreen.main
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // Start with ignoresMouseEvents = true so clicks around/below the notch always pass through to apps like Safari
        self.ignoresMouseEvents = true
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }
}

/// Custom NSHostingView that directly handles macOS Drag & Drop (`NSDraggingDestination`)
/// at the root view level so dragging any number of JPEG/PNG/files from Finder, Downloads, or Desktop
/// into the left multi-image shelf or right AirDrop zone works 100% of the time.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var activeNotchSizeProvider: (() -> CGSize)?
    weak var stateModel: NotchStateModel?

    private var supportedDragTypes: [NSPasteboard.PasteboardType] {
        return [
            .fileURL,
            .URL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.image")
        ]
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(supportedDragTypes)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(supportedDragTypes)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        self.window?.makeKey()
        super.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let size = activeNotchSizeProvider?() else {
            return super.hitTest(point)
        }
        // Strict hit-test strictly inside the visible notch silhouette (zero extra padding around or below)
        let notchRect = NSRect(
            x: (bounds.width - size.width) / 2.0,
            y: bounds.height - size.height,
            width: size.width,
            height: size.height
        )
        if notchRect.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }

    // MARK: - Root NSDraggingDestination Implementation
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(with: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(with: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDragHighlight()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearDragHighlight()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let localPoint = convert(sender.draggingLocation, from: nil)
        let isRightSideAirDrop = (localPoint.x >= bounds.midX)
        clearDragHighlight()

        let droppedURLs = extractFileURLs(from: sender.draggingPasteboard)
        guard !droppedURLs.isEmpty else {
            return false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if isRightSideAirDrop {
                if let firstURL = droppedURLs.first {
                    FileConverterService.shared.triggerAirDrop(for: firstURL, anchorView: self)
                }
            } else {
                self.stateModel?.addShelfFiles(droppedURLs)
            }
        }
        return true
    }

    private func updateDragState(with sender: NSDraggingInfo) {
        let localPoint = convert(sender.draggingLocation, from: nil)
        let isRightSide = (localPoint.x >= bounds.midX)

        DispatchQueue.main.async { [weak self] in
            guard let model = self?.stateModel else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.isHovering = true
                model.activeTab = .tray
                model.isDraggingOverLeftShelf = !isRightSide
                model.isDraggingOverRightAirDrop = isRightSide
            }
        }
    }

    private func clearDragHighlight() {
        DispatchQueue.main.async { [weak self] in
            guard let model = self?.stateModel else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.isDraggingOverLeftShelf = false
                model.isDraggingOverRightAirDrop = false
            }
        }
    }

    private func extractFileURLs(from pb: NSPasteboard) -> [URL] {
        // 1. Read NSURL objects directly (Finder / Downloads / Desktop files)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                return fileURLs
            }
        }

        // 2. Check NSFilenamesPboardType array
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pb.propertyList(forType: filenamesType) as? [String],
           !paths.isEmpty {
            return paths.map { URL(fileURLWithPath: $0) }
        }

        // 3. Check raw public.file-url string
        if let urlStr = pb.string(forType: .fileURL),
           let url = URL(string: urlStr), url.isFileURL {
            return [url]
        }

        // 4. Check raw NSImage dragged from a browser or app
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let firstImage = images.first,
           let tempURL = saveTemporaryPNG(firstImage) {
            return [tempURL]
        }

        if let tiffData = pb.data(forType: .tiff), let img = NSImage(data: tiffData), let tempURL = saveTemporaryPNG(img) {
            return [tempURL]
        }
        if let pngData = pb.data(forType: .png), let img = NSImage(data: pngData), let tempURL = saveTemporaryPNG(img) {
            return [tempURL]
        }

        return []
    }

    private func saveTemporaryPNG(_ image: NSImage) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagenApoyada_\(Int(Date().timeIntervalSince1970)).png")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        try? pngData.write(to: tempURL, options: .atomic)
        return tempURL
    }
}
