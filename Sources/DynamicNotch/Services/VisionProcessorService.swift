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

            // 1. Primary AI Segmentation Engine: High-Precision RMBG-1.4 / U2-Net ONNX Neural Network (macOS 12+)
            if self.runNeuralBackgroundRemoval(inputURL: imageURL, outputURL: destinationURL) {
                let downloadsDir = destinationURL.deletingLastPathComponent().path
                NSWorkspace.shared.noteFileSystemChanged(downloadsDir)
                DispatchQueue.main.async {
                    completion(.success(destinationURL))
                }
                return
            }

            // 2. Fallback: Native Vision Framework
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(.failure(VisionProcessorError.invalidImage))
                }
                return
            }

            if #available(macOS 14.0, *) {
                if let outputURL = try? self.removeBackgroundMacOS14(cgImage: cgImage, destinationURL: destinationURL) {
                    DispatchQueue.main.async {
                        completion(.success(outputURL))
                    }
                    return
                }
            }

            do {
                let outputURL = try self.removeBackgroundMacOS12Fallback(cgImage: cgImage, destinationURL: destinationURL)
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

    private func makeUniqueDownloadsPNGURL(for originalURL: URL) -> URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? originalURL.deletingLastPathComponent()
        var baseName = originalURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix("_sin_fondo") {
            baseName = String(baseName.dropLast("_sin_fondo".count))
        }
        if baseName.hasSuffix("_nobg") {
            baseName = String(baseName.dropLast("_nobg".count))
        }

        var outURL = downloadsDir.appendingPathComponent("\(baseName)_sin_fondo.png")
        var counter = 2
        while FileManager.default.fileExists(atPath: outURL.path) {
            outURL = downloadsDir.appendingPathComponent("\(baseName)_sin_fondo_\(counter).png")
            counter += 1
        }
        return outURL
    }

    private func runNeuralBackgroundRemoval(inputURL: URL, outputURL: URL) -> Bool {
        let bundleRes = Bundle.main.resourceURL
        let candidateScripts = [
            bundleRes?.appendingPathComponent("remove_bg_ai.py").path,
            "/Users/ivanlevy/Desktop/DynamicNotch/remove_bg_ai.py"
        ].compactMap { $0 }

        let candidateModels = [
            bundleRes?.appendingPathComponent("rmbg-1.4.onnx").path,
            "/Users/ivanlevy/Desktop/DynamicNotch/rmbg-1.4.onnx",
            bundleRes?.appendingPathComponent("u2netp.onnx").path,
            "/Users/ivanlevy/Desktop/DynamicNotch/u2netp.onnx"
        ].compactMap { $0 }

        let candidatePythons = [
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3"
        ]

        guard let scriptPath = candidateScripts.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let modelPath = candidateModels.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let pythonPath = candidatePythons.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            NSLog("[VisionProcessorService] Script, model or python executable not found.")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, inputURL.path, outputURL.path, modelPath]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                    NSLog("[VisionProcessorService] Python error (%d): %@", process.terminationStatus, errStr)
                }
            }
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path)
        } catch {
            NSLog("[VisionProcessorService] Execution exception: %@", error.localizedDescription)
            return false
        }
    }

    @available(macOS 14.0, *)
    private func removeBackgroundMacOS14(cgImage: CGImage, destinationURL: URL) throws -> URL {
        #if compiler(>=5.9)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first else {
            throw VisionProcessorError.maskGenerationFailed
        }
        let maskedBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return try applyMaskBuffer(maskedBuffer, to: cgImage, destinationURL: destinationURL)
        #else
        if let requestClass = NSClassFromString("VNGenerateForegroundInstanceMaskRequest") as? VNImageBasedRequest.Type {
            let request = requestClass.init()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            if let firstObs = request.results?.first as? VNPixelBufferObservation {
                return try applyMaskBuffer(firstObs.pixelBuffer, to: cgImage, destinationURL: destinationURL)
            }
        }
        return try removeBackgroundMacOS12Fallback(cgImage: cgImage, destinationURL: destinationURL)
        #endif
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
