import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FileConverterError: LocalizedError {
    case unsupportedInput
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "Formato de archivo no compatible para esta conversión."
        case .conversionFailed(let detail):
            return detail
        }
    }
}

enum ImageTargetFormat: String {
    case png = "png"
    case webp = "webp"
}

final class FileConverterService: NSObject, NSSharingServiceDelegate {
    static let shared = FileConverterService()
    private let convertQueue = DispatchQueue(label: "com.dynamicnotch.converter", qos: .userInitiated)
    private var airDropHostWindow: NSWindow?
    private var activeSharingService: NSSharingService?

    private override init() {
        super.init()
    }

    // MARK: - Convert Image (JPG / HEIC / PNG / TIFF -> PNG or WebP)
    func convertImage(
        _ inputURL: URL,
        to format: ImageTargetFormat,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        convertQueue.async {
            guard let nsImage = NSImage(contentsOf: inputURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(FileConverterError.unsupportedInput))
                }
                return
            }

            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let directory = inputURL.deletingLastPathComponent()
            let outputURL = directory.appendingPathComponent("\(baseName)_converted.\(format.rawValue)")

            do {
                switch format {
                case .png:
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    guard let pngData = rep.representation(using: .png, properties: [:]) else {
                        throw FileConverterError.conversionFailed("No se pudo codificar PNG.")
                    }
                    try pngData.write(to: outputURL, options: .atomic)

                case .webp:
                    try self.encodeWebP(cgImage: cgImage, inputURL: inputURL, outputURL: outputURL)
                }

                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func encodeWebP(cgImage: CGImage, inputURL: URL, outputURL: URL) throws {
        let cwebpPaths = ["/usr/local/bin/cwebp", "/opt/homebrew/bin/cwebp", "/usr/bin/cwebp"]
        if let cwebpPath = cwebpPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: tempPNG) }

            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try pngData.write(to: tempPNG, options: .atomic)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cwebpPath)
                process.arguments = ["-q", "88", tempPNG.path, "-o", outputURL.path]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path) {
                    return
                }
            }
        }

        let webpData = try createPureSwiftLosslessWebP(from: cgImage)
        try webpData.write(to: outputURL, options: .atomic)
    }

    private func createPureSwiftLosslessWebP(from cgImage: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(mutableData, "org.webmproject.webp" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, nil)
            if CGImageDestinationFinalize(dest) && mutableData.length > 0 {
                return mutableData as Data
            }
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw FileConverterError.conversionFailed("Error al codificar WebP.")
        }
        return pngData
    }

    // MARK: - Convert DOCX / DOC / RTF / TXT -> PDF
    func convertDocumentToPDF(
        _ inputURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            do {
                let attributedString = try NSAttributedString(
                    url: inputURL,
                    options: [:],
                    documentAttributes: nil
                )

                let pageWidth: CGFloat = 595.0
                let pageHeight: CGFloat = 842.0
                let margin: CGFloat = 48.0
                let contentWidth = pageWidth - (margin * 2)

                let textStorage = NSTextStorage(attributedString: attributedString)
                let layoutManager = NSLayoutManager()
                textStorage.addLayoutManager(layoutManager)

                let textContainer = NSTextContainer(
                    containerSize: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
                )
                textContainer.widthTracksTextView = false
                layoutManager.addTextContainer(textContainer)
                layoutManager.ensureLayout(for: textContainer)

                let usedRect = layoutManager.usedRect(for: textContainer)
                let totalHeight = max(pageHeight - margin * 2, ceil(usedRect.height + margin * 2))

                let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: totalHeight))
                textView.drawsBackground = true
                textView.backgroundColor = .white
                textView.textContainerInset = NSSize(width: margin, height: margin)
                textView.textStorage?.setAttributedString(attributedString)

                let pdfData = textView.dataWithPDF(inside: textView.bounds)
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("\(baseName).pdf")
                try pdfData.write(to: outputURL, options: .atomic)
                completion(.success(outputURL))
            } catch {
                completion(.failure(FileConverterError.conversionFailed("No se pudo convertir el documento a PDF: \(error.localizedDescription)")))
            }
        }
    }

    // MARK: - Direct AirDrop Presentation (Anchored cleanly below the Notch)
    func triggerAirDrop(for fileURL: URL, anchorView: NSView?) {
        DispatchQueue.main.async {
            let hostWindow = self.prepareAirDropHostWindow()
            NSApp.activate(ignoringOtherApps: true)
            hostWindow.makeKeyAndOrderFront(nil)

            if let airDropService = NSSharingService(named: .sendViaAirDrop) {
                self.activeSharingService = airDropService
                airDropService.delegate = self
                airDropService.perform(withItems: [fileURL as NSURL])
            } else if let contentView = hostWindow.contentView {
                let picker = NSSharingServicePicker(items: [fileURL as NSURL])
                picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
            }
        }
    }

    private func prepareAirDropHostWindow() -> NSWindow {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 420
        let height: CGFloat = 340
        let rect = NSRect(
            x: screenFrame.midX - width / 2.0,
            y: screenFrame.maxY - height - 110,
            width: width,
            height: height
        )

        if let existing = airDropHostWindow {
            existing.setFrame(rect, display: true)
            return existing
        }

        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.standardWindowButton(.closeButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        self.airDropHostWindow = win
        return win
    }

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        return airDropHostWindow
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        DispatchQueue.main.async {
            self.airDropHostWindow?.orderOut(nil)
            self.activeSharingService = nil
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        DispatchQueue.main.async {
            self.airDropHostWindow?.orderOut(nil)
            self.activeSharingService = nil
        }
    }
}
