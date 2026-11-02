import Foundation
import AVFoundation
import AppKit

final class ScreenRecorderService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    static let shared = ScreenRecorderService()

    @Published var isRecording: Bool = false
    @Published var recordingDuration: Double = 0.0
    @Published var isPreparing: Bool = false
    @Published var lastRecordedURL: URL? = nil

    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var durationTimer: Timer?
    private let recordingQueue = DispatchQueue(label: "com.dynamicnotch.recorder", qos: .userInitiated)

    var formattedDuration: String {
        let total = Int(recordingDuration)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private override init() {
        super.init()
    }

    func toggleRecording(statusHandler: @escaping (String, Bool) -> Void) {
        if isRecording {
            stopRecording(statusHandler: statusHandler)
        } else {
            startRecording(statusHandler: statusHandler)
        }
    }

    func startRecording(statusHandler: @escaping (String, Bool) -> Void) {
        guard !isRecording, !isPreparing else { return }

        // Check screen recording permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            statusHandler("Otorga permiso de Grabación de pantalla en Ajustes", true)
            return
        }

        isPreparing = true
        statusHandler("Preparando grabación...", false)

        recordingQueue.async { [weak self] in
            guard let self = self else { return }

            let session = AVCaptureSession()
            session.sessionPreset = .high

            // 1. Screen input
            guard let screenInput = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
                DispatchQueue.main.async {
                    self.isPreparing = false
                    statusHandler("No se pudo capturar la pantalla", true)
                }
                return
            }
            screenInput.capturesCursor = true
            screenInput.capturesMouseClicks = true

            if session.canAddInput(screenInput) {
                session.addInput(screenInput)
            } else {
                DispatchQueue.main.async {
                    self.isPreparing = false
                    statusHandler("No se pudo añadir pantalla", true)
                }
                return
            }

            // 2. Microphone audio input (captures mic and ambient/speakers sound)
            if let micDevice = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: micDevice) {
                if session.canAddInput(micInput) {
                    session.addInput(micInput)
                }
            }

            // 3. Movie file output
            let output = AVCaptureMovieFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                DispatchQueue.main.async {
                    self.isPreparing = false
                    statusHandler("Error configurando salida de video", true)
                }
                return
            }

            self.captureSession = session
            self.movieFileOutput = output

            session.startRunning()

            // Prepare destination file URL in ~/Movies
            let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "Grabacion_\(dateFormatter.string(from: Date())).mov"
            let outputURL = moviesDir.appendingPathComponent(fileName)

            try? FileManager.default.removeItem(at: outputURL)

            DispatchQueue.main.async {
                self.recordingDuration = 0.0
                output.startRecording(to: outputURL, recordingDelegate: self)
                self.isPreparing = false
                self.isRecording = true
                statusHandler("Grabando pantalla...", false)

                self.durationTimer?.invalidate()
                self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, self.isRecording else { return }
                    self.recordingDuration += 1.0
                }
            }
        }
    }

    func stopRecording(statusHandler: @escaping (String, Bool) -> Void) {
        guard isRecording else { return }
        statusHandler("Guardando video...", false)

        durationTimer?.invalidate()
        durationTimer = nil

        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieFileOutput?.stopRecording()
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.movieFileOutput = nil

            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.durationTimer?.invalidate()
            self.durationTimer = nil

            if let error = error as NSError?, error.code != noErr {
                // Check if file still exists and has content despite non-fatal warning
                if FileManager.default.fileExists(atPath: outputFileURL.path),
                   let attr = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
                   (attr[.size] as? Int64 ?? 0) > 0 {
                    self.lastRecordedURL = outputFileURL
                    NSWorkspace.shared.activateFileViewerSelecting([outputFileURL])
                }
            } else {
                self.lastRecordedURL = outputFileURL
                // Reveal in Finder
                NSWorkspace.shared.activateFileViewerSelecting([outputFileURL])
            }
        }
    }
}
