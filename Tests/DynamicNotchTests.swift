import Foundation
import AppKit
import CoreGraphics
import QuartzCore

@main
struct DynamicNotchTestRunner {
    static var passed = 0
    static var failed = 0

    static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
            print("  ✅ PASS: \(message)")
        } else {
            failed += 1
            print("  ❌ FAIL: \(message)")
        }
    }

    static func main() {
        print("====================================================")
        print("🧪 EJECUTANDO SUITE DE TESTS DE DYNAMICNOTCH")
        print("====================================================\n")

        testStateModelAndRowsOfThree()
        testTabPersistenceForCameraMirror()
        testCameraMirrorLayerTransform()
        testAirDropServiceAvailability()
        testAppBundleAndResourcesIntegrity()
        testEndToEndNeuralBackgroundRemoval()

        print("\n====================================================")
        print("📊 RESULTADO FINAL: \(passed) pasaron, \(failed) fallaron")
        print("====================================================")

        if failed > 0 {
            Foundation.exit(1)
        }
    }

    // 1. Test Hileras de a 3 (3-column grid rows & dynamic height expansion)
    static func testStateModelAndRowsOfThree() {
        print("▶️ [Test 1] Hileras de a 3 en el estante de imágenes (NotchStateModel)")
        let model = NotchStateModel()
        model.isHovering = true
        model.activeTab = .tray

        assert(model.shelfItems.isEmpty, "El estante inicia vacío")
        assert(model.visibleShelfRows == 1, "Sin imágenes, visibleShelfRows es 1")
        assert(model.trayModuleHeight == 54, "Con 0 imágenes, trayModuleHeight es 54 pt")

        // Crear 7 URLs de prueba
        let urls = (1...7).map { URL(fileURLWithPath: "/tmp/test_img_\($0).png") }

        // Agregar 3 imágenes (1ra hilera de 3)
        let exp1 = CFRunLoopGetCurrent()
        model.addShelfFiles(Array(urls[0..<3]))
        CFRunLoopRunInMode(.defaultMode, 0.1, false)
        _ = exp1

        assert(model.shelfItems.count == 3, "Se almacenaron exactamente 3 imágenes en la primera hilera")
        assert(model.visibleShelfRows == 1, "Con 3 imágenes (1 hilera de 3), visibleShelfRows == 1")
        assert(model.trayModuleHeight == 54, "Con 1 hilera de 3 imágenes, trayModuleHeight == 54 pt")
        assert(model.shelfItems[0].originalURL.lastPathComponent == "test_img_1.png", "Orden izquierda a derecha preservado (ítem 1)")
        assert(model.shelfItems[2].originalURL.lastPathComponent == "test_img_3.png", "Orden izquierda a derecha preservado (ítem 3)")

        // Agregar 2 imágenes más -> 5 imágenes (2da hilera de 3)
        model.addShelfFiles(Array(urls[3..<5]))
        CFRunLoopRunInMode(.defaultMode, 0.1, false)

        assert(model.shelfItems.count == 5, "Se almacenaron 5 imágenes en total")
        assert(model.visibleShelfRows == 2, "Con 5 imágenes (2 hileras de 3), visibleShelfRows == 2")
        assert(model.trayModuleHeight == 100, "Con 2 hileras de 3, el módulo se expande a 100 pt")
        assert(model.targetHeight == 152, "El notch se expande verticalmente a 152 pt para mostrar 2 hileras")

        // Agregar 2 imágenes más -> 7 imágenes (3ra hilera de 3)
        model.addShelfFiles(Array(urls[5..<7]))
        CFRunLoopRunInMode(.defaultMode, 0.1, false)

        assert(model.shelfItems.count == 7, "Se almacenaron 7 imágenes en total")
        assert(model.visibleShelfRows == 3, "Con 7 imágenes (3 hileras de 3), visibleShelfRows == 3")
        assert(model.trayModuleHeight == 146, "Con 3 hileras de 3, el módulo se expande a 146 pt")
        assert(model.targetHeight == 198, "El notch se expande verticalmente a 198 pt para mostrar 3 hileras")

        // Limpiar estante
        model.clearAllShelfItems()
        CFRunLoopRunInMode(.defaultMode, 0.1, false)
        assert(model.shelfItems.isEmpty, "clearAllShelfItems vacía todas las imágenes correctamente")
    }

    // 2. Test que la pestaña de cámara no vuelva sola a archivos
    static func testTabPersistenceForCameraMirror() {
        print("\n▶️ [Test 2] Persistencia de la pestaña Espejo de Cámara (.camera)")
        let model = NotchStateModel()
        model.isHovering = true
        model.activeTab = .camera

        assert(model.activeTab == .camera, "La pestaña activa es .camera")
        assert(model.targetHeight == 116, "Altura en modo cámara es 116 pt (52 + 64)")

        // Simular estado sin arrastre externo
        model.isDraggingOverLeftShelf = false
        model.isDraggingOverRightAirDrop = false
        assert(model.activeTab == .camera, "Al hacer clic normal sin arrastrar archivos, permanece en .camera")
    }

    // 3. Test del Espejo Circular de Cámara (Transformación centrada)
    static func testCameraMirrorLayerTransform() {
        print("\n▶️ [Test 3] Espejo Circular de Cámara (CameraPreviewContainerView)")
        let service = CameraMirrorService()
        let previewView = CameraPreviewContainerView(session: service.captureSession)
        previewView.frame = NSRect(x: 0, y: 0, width: 62, height: 62)
        previewView.layout()

        let sublayers: [CALayer] = previewView.layer?.sublayers ?? []
        if let sublayer = sublayers.first {
            assert(sublayer.anchorPoint == CGPoint(x: 0.5, y: 0.5), "anchorPoint centrado en (0.5, 0.5) para evitar desplazamiento fuera del círculo")
            assert(sublayer.position == CGPoint(x: 31.0, y: 31.0), "Posición de capa centrada en (31, 31)")
            let transform = sublayer.affineTransform()
            assert(transform.a == -1.0 && transform.d == 1.0, "Efecto espejo horizontal activo (scaleX = -1, scaleY = 1)")
        } else {
            assert(false, "Sublayer de previsualización de cámara creada")
        }
    }

    // 4. Test del Servicio Nativo de AirDrop
    static func testAirDropServiceAvailability() {
        print("\n▶️ [Test 4] Integración con macOS AirDrop (NSSharingService)")
        let airDropService = NSSharingService(named: .sendViaAirDrop)
        assert(airDropService != nil, "NSSharingService(.sendViaAirDrop) está disponible en macOS")
    }

    // 5. Test de Integridad del Bundle Notch.app y Modelo IA
    static func testAppBundleAndResourcesIntegrity() {
        print("\n▶️ [Test 5] Integridad de Notch.app y Recursos IA")
        let fm = FileManager.default
        let appPath = "/Users/ivanlevy/Desktop/DynamicNotch/Notch.app"
        let binPath = "\(appPath)/Contents/MacOS/Notch"
        let modelPath = "\(appPath)/Contents/Resources/u2netp.onnx"
        let scriptPath = "\(appPath)/Contents/Resources/remove_bg_ai.py"
        let zipPath = "/Users/ivanlevy/Desktop/DynamicNotch/Notch.zip"

        assert(fm.isExecutableFile(atPath: binPath), "Binario ejecutable Notch presente en Contents/MacOS")
        assert(fm.fileExists(atPath: modelPath), "Modelo neuronal u2netp.onnx incluido en Contents/Resources")
        if let attrs = try? fm.attributesOfItem(atPath: modelPath),
           let size = attrs[.size] as? UInt64 {
            assert(size > 40_000_000, "Modelo neuronal Silueta/U²-Net de alta precisión (\(size / 1_000_000) MB) verificado")
        } else {
            assert(false, "Tamaño de u2netp.onnx verificado")
        }
        assert(fm.isExecutableFile(atPath: scriptPath), "Script neuronal remove_bg_ai.py incluido y ejecutable en Contents/Resources")
        assert(fm.fileExists(atPath: zipPath), "Paquete distribuible Notch.zip presente")
    }

    // 6. Test End-to-End de Recorte de Fondo con IA y Descarga de PNG Transparente
    static func testEndToEndNeuralBackgroundRemoval() {
        print("\n▶️ [Test 6] Recorte de Fondo End-to-End (VisionProcessorService + Red Neuronal ONNX)")
        let fm = FileManager.default

        // Crear una imagen de prueba o usar la imagen de muestra si existe
        let samplePath = "/Users/ivanlevy/Downloads/Libro de Memorias con Mascotas.jpg"
        let tempInputURL = URL(fileURLWithPath: "/tmp/unit_test_mascota.jpg")
        defer {
            try? fm.removeItem(at: tempInputURL)
        }

        if fm.fileExists(atPath: samplePath) {
            try? fm.removeItem(at: tempInputURL)
            try? fm.copyItem(atPath: samplePath, toPath: tempInputURL.path)
        } else {
            // Generar imagen sintética si no existiera la muestra
            let img = NSImage(size: NSSize(width: 320, height: 320))
            img.lockFocus()
            NSColor.brown.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 320)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 80, y: 80, width: 160, height: 160)).fill()
            img.unlockFocus()
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let jpg = rep.representation(using: .jpeg, properties: [:]) {
                try? jpg.write(to: tempInputURL)
            }
        }

        var finished = false
        var outputURLResult: URL? = nil
        var errorResult: Error? = nil

        VisionProcessorService.shared.removeBackground(from: tempInputURL, geminiApiKey: "") { result in
            switch result {
            case .success(let url):
                outputURLResult = url
            case .failure(let err):
                errorResult = err
            }
            finished = true
        }

        let start = Date()
        while !finished && Date().timeIntervalSince(start) < 25.0 {
            CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }

        assert(finished, "El procesamiento de eliminación de fondo finalizó a tiempo")
        assert(errorResult == nil, "Sin errores durante la eliminación de fondo")

        if let outURL = outputURLResult {
            defer {
                // Limpiar el archivo generado por el test para no ensuciar Descargas
                try? fm.removeItem(at: outURL)
            }
            assert(fm.fileExists(atPath: outURL.path), "Archivo PNG generado en Descargas: \(outURL.lastPathComponent)")
            assert(outURL.pathExtension.lowercased() == "png", "El archivo exportado tiene extensión .png")
            assert(outURL.deletingLastPathComponent().lastPathComponent == "Downloads", "El archivo se descargó directamente en ~/Downloads")

            if let outImg = NSImage(contentsOf: outURL),
               let cgImg = outImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let w = cgImg.width
                let h = cgImg.height
                assert(w > 0 && h > 0, "Dimensiones del PNG válidas (\(w)x\(h))")

                // Verificar canal alfa real (píxeles transparentes vs opacos)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                var rawData = [UInt8](repeating: 0, count: w * h * 4)
                if let ctx = CGContext(
                    data: &rawData,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
                    var transparentCount = 0
                    var opaqueCount = 0
                    let totalPixels = w * h
                    for i in stride(from: 3, to: rawData.count, by: 4) {
                        let a = rawData[i]
                        if a < 15 { transparentCount += 1 }
                        else if a > 200 { opaqueCount += 1 }
                    }
                    let transRatio = Double(transparentCount) / Double(totalPixels)
                    let opaqueRatio = Double(opaqueCount) / Double(totalPixels)
                    print(String(format: "     -> Píxeles transparentes: %.1f%% | Píxeles de sujeto opacos: %.1f%%", transRatio * 100, opaqueRatio * 100))
                    assert(transRatio > 0.25, "El fondo fue eliminado con transparencia real (>25% transparente)")
                    assert(opaqueRatio > 0.10, "El sujeto principal fue conservado con opacidad (>10% opaco)")
                }
            } else {
                assert(false, "Se pudo abrir el PNG generado para verificar su canal alfa")
            }
        } else {
            assert(false, "Se obtuvo URL del PNG sin fondo")
        }
    }
}
