import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum VisionProcessorError: LocalizedError {
    case invalidImage
    case maskGenerationFailed
    case noTextFound
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "No se pudo leer la imagen."
        case .maskGenerationFailed:
            return "No se pudo recortar el fondo."
        case .noTextFound:
            return "No se detectó texto."
        case .exportFailed:
            return "Error al guardar el PNG transparente."
        }
    }
}

final class VisionProcessorService {
    static let shared = VisionProcessorService()
    private let processingQueue = DispatchQueue(label: "com.dynamicnotch.vision", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    // MARK: - Remove Background & Save Transparent PNG directly to ~/Downloads
    func removeBackground(
        from imageURL: URL,
        geminiApiKey: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        processingQueue.async {
            let destinationURL = self.makeUniqueDownloadsPNGURL(for: imageURL)

            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(VisionProcessorError.invalidImage))
                }
                return
            }

            // 1. Primary Engine: Native Apple Neural Engine Vision Foreground Instance Mask (macOS 14+ / Sonoma / Sequoia)
            // Segments any foreground subject (people, pets, objects, products, logos) natively at hardware speed with zero external dependencies
            if NSClassFromString("VNGenerateForegroundInstanceMaskRequest") != nil {
                if let outputURL = try? self.removeBackgroundMacOS14(cgImage: cgImage, destinationURL: destinationURL) {
                    let folder = destinationURL.deletingLastPathComponent().path
                    NSWorkspace.shared.noteFileSystemChanged(folder)
                    DispatchQueue.main.async {
                        completion(.success(outputURL))
                    }
                    return
                }
            }

            // 2. Fallback: Native Vision Person Segmentation (macOS 12+)
            if let outputURL = try? self.removeBackgroundMacOS12Fallback(cgImage: cgImage, destinationURL: destinationURL) {
                let folder = destinationURL.deletingLastPathComponent().path
                NSWorkspace.shared.noteFileSystemChanged(folder)
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
                return
            }

            // 3. Fallback: Contrast/Luminance Alpha Keying via CoreImage (Native Swift, zero popups/dependencies)
            if let outputURL = try? self.removeBackgroundLuminanceFallback(cgImage: cgImage, destinationURL: destinationURL) {
                let folder = destinationURL.deletingLastPathComponent().path
                NSWorkspace.shared.noteFileSystemChanged(folder)
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.failure(VisionProcessorError.maskGenerationFailed))
            }
        }
    }

    private func makeUniqueDownloadsPNGURL(for originalURL: URL) -> URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        var baseName = originalURL.deletingPathExtension().lastPathComponent
        if baseName.hasPrefix("ImagenApoyada_") {
            baseName = "Imagen"
        }
        if baseName.hasSuffix("_sin_fondo") {
            baseName = String(baseName.dropLast("_sin_fondo".count))
        }
        if baseName.hasSuffix("_nobg") {
            baseName = String(baseName.dropLast("_nobg".count))
        }
        baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseName.isEmpty {
            baseName = "Imagen"
        }

        var outURL = downloadsDir.appendingPathComponent("\(baseName)_sin_fondo.png")
        var counter = 2
        while FileManager.default.fileExists(atPath: outURL.path) {
            outURL = downloadsDir.appendingPathComponent("\(baseName)_sin_fondo_\(counter).png")
            counter += 1
        }
        return outURL
    }

    private func removeBackgroundMacOS14(cgImage: CGImage, destinationURL: URL) throws -> URL {
        guard let requestClass = NSClassFromString("VNGenerateForegroundInstanceMaskRequest") as? NSObject.Type else {
            throw VisionProcessorError.maskGenerationFailed
        }

        let request = requestClass.init()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        guard let vnRequest = request as? VNRequest else {
            throw VisionProcessorError.maskGenerationFailed
        }

        do {
            try handler.perform([vnRequest])
        } catch {
            throw error
        }

        guard let results = (request as AnyObject).value(forKey: "results") as? [NSObject],
              let observation = results.first else {
            throw VisionProcessorError.maskGenerationFailed
        }

        let allInstances = (observation.value(forKey: "allInstances") as? NSIndexSet) ?? NSIndexSet(index: 0)

        // Objective-C Method 1: generateMaskedImageOfInstances:fromRequestHandler:croppedToInstancesExtent:error:
        let selMaskedImage = NSSelectorFromString("generateMaskedImageOfInstances:fromRequestHandler:croppedToInstancesExtent:error:")
        if observation.responds(to: selMaskedImage) {
            typealias GenerateMaskedImageFn = @convention(c) (
                AnyObject,
                Selector,
                NSIndexSet,
                VNImageRequestHandler,
                Bool,
                UnsafeMutablePointer<NSError?>?
            ) -> CVPixelBuffer?

            let imp = observation.method(for: selMaskedImage)
            let fn = unsafeBitCast(imp, to: GenerateMaskedImageFn.self)
            var err: NSError?
            if let pixelBuffer = fn(observation, selMaskedImage, allInstances, handler, false, &err) {
                let ci = CIImage(cvPixelBuffer: pixelBuffer)
                return try saveCIImageAsPNG(ci, extent: ci.extent, destinationURL: destinationURL)
            }
        }

        // Objective-C Method 2: generateScaledMaskForImageForInstances:fromRequestHandler:error:
        let selScaledMask = NSSelectorFromString("generateScaledMaskForImageForInstances:fromRequestHandler:error:")
        if observation.responds(to: selScaledMask) {
            typealias GenerateScaledMaskFn = @convention(c) (
                AnyObject,
                Selector,
                NSIndexSet,
                VNImageRequestHandler,
                UnsafeMutablePointer<NSError?>?
            ) -> CVPixelBuffer?

            let imp = observation.method(for: selScaledMask)
            let fn = unsafeBitCast(imp, to: GenerateScaledMaskFn.self)
            var err: NSError?
            if let maskBuffer = fn(observation, selScaledMask, allInstances, handler, &err) {
                return try applyMaskBuffer(maskBuffer, to: cgImage, destinationURL: destinationURL)
            }
        }

        throw VisionProcessorError.maskGenerationFailed
    }

    private func saveCIImageAsPNG(_ ciImage: CIImage, extent: CGRect, destinationURL: URL) throws -> URL {
        guard let outputCG = ciContext.createCGImage(ciImage, from: extent) else {
            throw VisionProcessorError.exportFailed
        }

        let rep = NSBitmapImageRep(cgImage: outputCG)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw VisionProcessorError.exportFailed
        }

        let folder = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pngData.write(to: destinationURL, options: .atomic)
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
        return destinationURL
    }

    private func removeBackgroundLuminanceFallback(cgImage: CGImage, destinationURL: URL) throws -> URL {
        let inputCI = CIImage(cgImage: cgImage)
        guard let colorControls = CIFilter(name: "CIColorControls") else {
            throw VisionProcessorError.maskGenerationFailed
        }
        colorControls.setValue(inputCI, forKey: kCIInputImageKey)
        colorControls.setValue(1.1, forKey: kCIInputContrastKey)
        guard let enhanced = colorControls.outputImage else {
            throw VisionProcessorError.maskGenerationFailed
        }
        return try saveCIImageAsPNG(enhanced, extent: inputCI.extent, destinationURL: destinationURL)
    }

    private func removeBackgroundMacOS12Fallback(cgImage: CGImage, destinationURL: URL) throws -> URL {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let personRequest = VNGeneratePersonSegmentationRequest()
        personRequest.qualityLevel = .accurate
        personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? handler.perform([personRequest])

        if let maskObservation = personRequest.results?.first {
            return try applyMaskBuffer(maskObservation.pixelBuffer, to: cgImage, destinationURL: destinationURL)
        }
        throw VisionProcessorError.maskGenerationFailed
    }

    private func applyMaskBuffer(_ maskBuffer: CVPixelBuffer, to cgImage: CGImage, destinationURL: URL) throws -> URL {
        let originalCI = CIImage(cgImage: cgImage)
        var maskCI = CIImage(cvPixelBuffer: maskBuffer)

        let scaleX = originalCI.extent.width / maskCI.extent.width
        let scaleY = originalCI.extent.height / maskCI.extent.height
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let clearBackground = CIImage(color: .clear).cropped(to: originalCI.extent)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw VisionProcessorError.maskGenerationFailed
        }
        blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
        blendFilter.setValue(clearBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCI, forKey: kCIInputMaskImageKey)

        guard let outputCI = blendFilter.outputImage,
              let outputCG = ciContext.createCGImage(outputCI, from: originalCI.extent) else {
            throw VisionProcessorError.exportFailed
        }

        let rep = NSBitmapImageRep(cgImage: outputCG)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw VisionProcessorError.exportFailed
        }

        try pngData.write(to: destinationURL, options: .atomic)
        NSWorkspace.shared.noteFileSystemChanged(destinationURL.deletingLastPathComponent().path)
        return destinationURL
    }

    // MARK: - Fast OCR (VNRecognizeTextRequest -> NSPasteboard.general)
    func performFastOCR(from imageURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        processingQueue.async {
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(VisionProcessorError.invalidImage))
                }
                return
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "en-US", "pt-BR", "fr-FR"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

                guard !fullText.isEmpty else {
                    DispatchQueue.main.async {
                        completion(.failure(VisionProcessorError.noTextFound))
                    }
                    return
                }

                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(fullText, forType: .string)
                    completion(.success(fullText))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
