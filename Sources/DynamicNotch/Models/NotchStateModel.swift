import Foundation
import AppKit
import SwiftUI

enum NotchExpansionState: Equatable {
    case idle
    case active
    case dragOver
}

enum NotchTab: String, CaseIterable, Equatable {
    case music
    case tray
    case camera
}

struct ShelfImageItem: Identifiable, Equatable {
    let id: UUID
    let originalURL: URL
    var activeURL: URL
    var thumbnail: NSImage
    var isProcessing: Bool = false
    var isTransparentPNG: Bool = false

    static func == (lhs: ShelfImageItem, rhs: ShelfImageItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.activeURL == rhs.activeURL &&
               lhs.isProcessing == rhs.isProcessing &&
               lhs.isTransparentPNG == rhs.isTransparentPNG
    }
}

final class NotchStateModel: ObservableObject {
    @Published var isHovering: Bool = false
    @Published var isDraggingOver: Bool = false
    @Published var isDraggingOverLeftShelf: Bool = false
    @Published var isDraggingOverRightAirDrop: Bool = false
    @Published var isPinnedOpen: Bool = false
    @Published var isManuallyCollapsed: Bool = false
    @Published var isNotchHidden: Bool = false
    @Published var activeTab: NotchTab = .music

    // Multi-Image Left Shelf (Apoyar todas las imágenes que quieras + Clic para quitar fondo y descargar PNG)
    @Published var shelfItems: [ShelfImageItem] = []
    @Published var statusBanner: String? = nil
    @Published var statusIsError: Bool = false

    // Ring light & Mirror state
    @Published var isRingLightOn: Bool = false
    @Published var ringLightWarmth: Double = 0.25 // 0.0 = Blanco Frío, 1.0 = Cálido
    @Published var isMirrorHovered: Bool = false

    // Optional Gemini API Key
    @Published var geminiApiKey: String {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: "DynamicNotch_GeminiAPIKey")
        }
    }

    private var statusClearWorkItem: DispatchWorkItem?

    init() {
        let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        let savedKey = UserDefaults.standard.string(forKey: "DynamicNotch_GeminiAPIKey") ?? ""
        self.geminiApiKey = !savedKey.isEmpty ? savedKey : envKey
    }

    var hasShelfItems: Bool {
        return !shelfItems.isEmpty
    }

    /// Number of rows of 3 images in the left shelf (minimum 1, visible without scrolling up to 3 rows)
    var visibleShelfRows: Int {
        guard !shelfItems.isEmpty else { return 1 }
        let totalRows = (shelfItems.count + 2) / 3
        return min(max(totalRows, 1), 3)
    }

    var trayModuleHeight: CGFloat {
        switch visibleShelfRows {
        case 1:
            return 54
        case 2:
            return 100
        default:
            return 146
        }
    }

    var isProcessingAny: Bool {
        return shelfItems.contains(where: { $0.isProcessing })
    }

    var expansionState: NotchExpansionState {
        if isManuallyCollapsed {
            return .idle
        }
        if isDraggingOver || isDraggingOverLeftShelf || isDraggingOverRightAirDrop {
            return .dragOver
        }
        if isHovering || isPinnedOpen || isProcessingAny {
            return .active
        }
        return .idle
    }

    var targetWidth: CGFloat {
        switch expansionState {
        case .idle:
            return 168
        case .active, .dragOver:
            return 408
        }
    }

    var targetHeight: CGFloat {
        switch expansionState {
        case .idle:
            return 24
        case .active:
            let moduleHeight: CGFloat
            switch activeTab {
            case .camera:
                moduleHeight = 68
            case .tray:
                moduleHeight = trayModuleHeight
            case .music:
                moduleHeight = 52
            }
            let base: CGFloat = 52 + moduleHeight
            return statusBanner != nil ? base + 14 : base
        case .dragOver:
            return 52 + trayModuleHeight
        }
    }

    var bottomCornerRadius: CGFloat {
        switch expansionState {
        case .idle:
            return 10
        case .active, .dragOver:
            return 22
        }
    }

    /// Immediately collapses the expanded notch back to compact menu-bar height and blocks hover re-expansion until cursor leaves.
    func collapseNotch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            self.isPinnedOpen = false
            self.isHovering = false
            self.isDraggingOver = false
            self.isDraggingOverLeftShelf = false
            self.isDraggingOverRightAirDrop = false
            self.isManuallyCollapsed = true
        }
    }

    func addShelfFiles(_ urls: [URL]) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                for url in urls {
                    let thumb = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path)
                    let item = ShelfImageItem(
                        id: UUID(),
                        originalURL: url,
                        activeURL: url,
                        thumbnail: thumb
                    )
                    self.shelfItems.append(item)
                }
                self.activeTab = .tray
            }
        }
    }

    func removeShelfItem(id: UUID) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.shelfItems.removeAll(where: { $0.id == id })
            }
        }
    }

    func clearAllShelfItems() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.shelfItems.removeAll()
            }
        }
    }

    /// Removes background from the clicked shelf item and downloads the transparent PNG into ~/Downloads
    func removeBackgroundForItem(id: UUID) {
        guard let index = shelfItems.firstIndex(where: { $0.id == id }),
              !shelfItems[index].isProcessing else { return }

        let inputURL = shelfItems[index].originalURL
        shelfItems[index].isProcessing = true

        VisionProcessorService.shared.removeBackground(
            from: inputURL,
            geminiApiKey: geminiApiKey
        ) { [weak self] result in
            guard let self = self else { return }
            guard let idx = self.shelfItems.firstIndex(where: { $0.id == id }) else { return }
            self.shelfItems[idx].isProcessing = false

            switch result {
            case .success(let downloadedPNGURL):
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.shelfItems[idx].activeURL = downloadedPNGURL
                    self.shelfItems[idx].isTransparentPNG = true
                    if let newThumb = NSImage(contentsOf: downloadedPNGURL) {
                        self.shelfItems[idx].thumbnail = newThumb
                    }
                }
                self.showTemporaryStatus("✓ Guardada en Descargas: \(downloadedPNGURL.lastPathComponent)", isError: false)
            case .failure(let error):
                self.showTemporaryStatus("Error: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func switchTabOnHover(_ tab: NotchTab) {
        guard activeTab != tab else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            self.activeTab = tab
        }
    }

    func showTemporaryStatus(_ message: String, isError: Bool = false, duration: TimeInterval = 3.0) {
        DispatchQueue.main.async {
            self.statusClearWorkItem?.cancel()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.statusBanner = message
                self.statusIsError = isError
            }

            let work = DispatchWorkItem { [weak self] in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self?.statusBanner = nil
                }
            }
            self.statusClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func showBanner(_ message: String, isError: Bool = false) {
        showTemporaryStatus(message, isError: isError)
    }
}
