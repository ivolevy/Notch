import Foundation
import AVFoundation
import AppKit
import SwiftUI

final class CameraMirrorService: NSObject, ObservableObject {
    @Published var isCameraActive: Bool = false
    @Published var statusText: String = "Cámara lista"
    @Published var userPausedCamera: Bool = false

    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.dynamicnotch.camera", qos: .userInitiated)
    private var isConfigured = false
    private var isStarting = false

    override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle Notifications
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidStartRunning),
            name: .AVCaptureSessionDidStartRunning,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidStopRunning),
            name: .AVCaptureSessionDidStopRunning,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChanged),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChanged),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    @objc private func handleSessionDidStartRunning() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isCameraActive = true
            self.isStarting = false
            self.statusText = "Espejo en vivo"
        }
    }

    @objc private func handleSessionDidStopRunning() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isCameraActive = false
            self.isStarting = false
            if self.statusText == "Espejo en vivo" || self.statusText == "Iniciando cámara..." {
                self.statusText = self.userPausedCamera ? "Espejo en pausa (clic para reanudar)" : "Espejo en pausa"
            }
        }
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
            NSLog("[CameraMirrorService] Session runtime error: %@", error.localizedDescription)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isCameraActive = false
            self.isStarting = false
            self.statusText = "Error en cámara"
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isConfigured = false
            if !self.userPausedCamera {
                self.configureAndStartSession()
            }
        }
    }

    @objc private func handleSessionWasInterrupted(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isCameraActive = false
            self.statusText = "Cámara ocupada por otra app"
        }
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusText = "Reanudando espejo..."
        }
        sessionQueue.async { [weak self] in
            guard let self = self, !self.userPausedCamera else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    @objc private func handleDeviceConnectionChanged() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isConfigured = false
            if self.captureSession.isRunning {
                self.configureAndStartSession()
            }
        }
    }

    // MARK: - Camera Controls
    func toggleCamera() {
        if isCameraActive || captureSession.isRunning {
            userPausedCamera = true
            stopCamera()
        } else {
            userPausedCamera = false
            startCamera()
        }
    }

    func startCameraIfNeeded() {
        guard !userPausedCamera else { return }
        startCamera()
    }

    func startCamera() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            DispatchQueue.main.async { [weak self] in
                self?.statusText = "Esperando permiso..."
                NSApp.activate(ignoringOtherApps: true)
            }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStartSession()
                    } else {
                        self?.isCameraActive = false
                        self?.statusText = "Permiso de cámara denegado"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.isCameraActive = false
                self?.statusText = "Activa Cámara en Preferencias"
            }
        @unknown default:
            break
        }
    }

    private func configureAndStartSession() {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "Iniciando cámara..."
            self?.isStarting = true
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.isConfigured || self.captureSession.inputs.isEmpty {
                self.captureSession.beginConfiguration()

                if self.captureSession.canSetSessionPreset(.high) {
                    self.captureSession.sessionPreset = .high
                } else {
                    self.captureSession.sessionPreset = .medium
                }

                for input in self.captureSession.inputs {
                    self.captureSession.removeInput(input)
                }

                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                    mediaType: .video,
                    position: .unspecified
                )
                let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video)

                if let videoDevice = device {
                    do {
                        let input = try AVCaptureDeviceInput(device: videoDevice)
                        if self.captureSession.canAddInput(input) {
                            self.captureSession.addInput(input)
                            self.isConfigured = true
                        }
                    } catch {
                        NSLog("[CameraMirrorService] Error creating device input: %@", error.localizedDescription)
                        self.isConfigured = false
                    }
                }
                self.captureSession.commitConfiguration()
            }

            if self.isConfigured {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                DispatchQueue.main.async {
                    self.isCameraActive = self.captureSession.isRunning
                    self.isStarting = false
                    if self.isCameraActive {
                        self.statusText = "Espejo en vivo"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isCameraActive = false
                    self.isStarting = false
                    self.statusText = "Cámara no detectada"
                }
            }
        }
    }

    func stopCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            DispatchQueue.main.async {
                self.isCameraActive = false
                self.isStarting = false
                self.statusText = "Espejo en pausa"
            }
        }
    }
}

// MARK: - Native AppKit Preview View
final class CameraPreviewContainerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let videoLayer = AVCaptureVideoPreviewLayer()
        videoLayer.videoGravity = .resizeAspectFill
        return videoLayer
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        applyNativeMirroring()
    }

    func applyNativeMirroring() {
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2.0
        applyNativeMirroring()
    }
}

// MARK: - SwiftUI Representable
struct WebcamCircularPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.setSession(session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerView, context: Context) {
        nsView.setSession(session)
        nsView.needsLayout = true
        nsView.layoutSubtreeIfNeeded()
    }
}
