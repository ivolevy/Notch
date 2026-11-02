import AppKit
import SwiftUI
import Combine

final class NotchWindowController {
    let panel: NotchPanel
    let stateModel: NotchStateModel
    let nowPlayingService: NowPlayingService
    let cameraService: CameraMirrorService

    private let canvasWidth: CGFloat = 440
    private let canvasHeight: CGFloat = 240
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragPollTimer: Timer?
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var hoverExitWorkItem: DispatchWorkItem?
    private var lastDragChangeCount: Int = NSPasteboard(name: .drag).changeCount
    private var cancellables = Set<AnyCancellable>()

    init(
        stateModel: NotchStateModel,
        nowPlayingService: NowPlayingService,
        cameraService: CameraMirrorService
    ) {
        self.stateModel = stateModel
        self.nowPlayingService = nowPlayingService
        self.cameraService = cameraService

        let initialRect = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        self.panel = NotchPanel(contentRect: initialRect)

        let rootView = DynamicNotchView(
            stateModel: stateModel,
            nowPlaying: nowPlayingService,
            cameraService: cameraService
        )

        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.frame = initialRect
        hostingView.stateModel = stateModel
        hostingView.activeNotchSizeProvider = { [weak stateModel] in
            guard let model = stateModel else { return CGSize(width: 168, height: 24) }
            return CGSize(width: model.targetWidth, height: model.targetHeight)
        }

        self.panel.ignoresMouseEvents = true
        self.panel.contentView = hostingView
        positionAtTopCenter()
        setupScreenAndMouseObservers()
        setupRingLightSubscription()
        setupVisibilitySubscription()
    }

    deinit {
        if let global = globalMouseMonitor {
            NSEvent.removeMonitor(global)
        }
        if let local = localMouseMonitor {
            NSEvent.removeMonitor(local)
        }
        dragPollTimer?.invalidate()
    }

    func show() {
        positionAtTopCenter()
        panel.orderFrontRegardless()
    }

    func positionAtTopCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.frame
        let x = screenFrame.midX - (canvasWidth / 2.0)
        let y = screenFrame.maxY - canvasHeight
        panel.setFrame(NSRect(x: x, y: y, width: canvasWidth, height: canvasHeight), display: true)
    }

    private func setupScreenAndMouseObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionAtTopCenter()
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        ) { [weak self] _ in
            self?.evaluatePointerLocation()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.evaluatePointerLocation()
            return event
        }

        dragPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.evaluatePointerLocation()
        }
    }

    private func evaluatePointerLocation() {
        if stateModel.isNotchHidden {
            if !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
            }
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let mouseLoc = NSEvent.mouseLocation
        let screenFrame = screen.frame
        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) != 0

        // Strict visible silhouette of the notch
        let activeW = stateModel.targetWidth
        let activeH = stateModel.targetHeight
        let notchScreenRect = NSRect(
            x: screenFrame.midX - activeW / 2.0,
            y: screenFrame.maxY - activeH,
            width: activeW,
            height: activeH
        )

        // Expanded hover zone: when already hovering or pinned open, allow a generous buffer
        // so switching between tabs with different widths (e.g. 560 to 408) never abruptly kicks the cursor out
        let insideNotch: Bool
        if stateModel.isHovering || stateModel.isPinnedOpen {
            let bufferW = max(activeW, 580)
            let bufferH = max(activeH, 130)
            let expandedHitRect = NSRect(
                x: screenFrame.midX - bufferW / 2.0,
                y: screenFrame.maxY - bufferH,
                width: bufferW,
                height: bufferH
            )
            insideNotch = expandedHitRect.contains(mouseLoc)
        } else {
            insideNotch = notchScreenRect.contains(mouseLoc)
        }

        let dragDetectionRect = NSRect(
            x: screenFrame.midX - (canvasWidth / 2.0),
            y: screenFrame.maxY - 140,
            width: canvasWidth,
            height: 140
        )
        let isNearTopWithMouseDown = isLeftMouseDown && dragDetectionRect.contains(mouseLoc)

        let currentDragCount = NSPasteboard(name: .drag).changeCount
        // Only treat as an external file drag if the system drag pasteboard changeCount actually changed!
        let isExternalFileDrag = isLeftMouseDown && (currentDragCount != lastDragChangeCount)

        if !isLeftMouseDown {
            lastDragChangeCount = currentDragCount
            if stateModel.isDraggingOverLeftShelf || stateModel.isDraggingOverRightAirDrop {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.stateModel.isDraggingOverLeftShelf = false
                        self.stateModel.isDraggingOverRightAirDrop = false
                    }
                }
            }
        }

        // Only auto-switch to .tray when dragging an external file from Finder/Desktop, NEVER on normal clicks!
        if isNearTopWithMouseDown && isExternalFileDrag {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            if !stateModel.isHovering || stateModel.activeTab != .tray {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        self.stateModel.isManuallyCollapsed = false
                        self.stateModel.isHovering = true
                        self.stateModel.activeTab = .tray
                    }
                }
            }
            return
        }

        if insideNotch {
            // Cursor is inside: cancel any pending exit timer immediately
            hoverExitWorkItem?.cancel()
            hoverExitWorkItem = nil

            // If user manually clicked "Contraer", only intercept mouse events inside the top 24pt pill
            if stateModel.isManuallyCollapsed {
                let collapsedRect = NSRect(
                    x: screenFrame.midX - 168.0 / 2.0,
                    y: screenFrame.maxY - 24.0,
                    width: 168.0,
                    height: 24.0
                )
                let insideCollapsedPill = collapsedRect.contains(mouseLoc)
                if panel.ignoresMouseEvents != !insideCollapsedPill {
                    panel.ignoresMouseEvents = !insideCollapsedPill
                }
                return
            }

            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }

            if !stateModel.isHovering && hoverExpandWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.hoverExpandWorkItem = nil
                    guard !self.stateModel.isNotchHidden && !self.stateModel.isManuallyCollapsed else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        self.stateModel.isHovering = true
                    }
                }
                hoverExpandWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
            }
        } else {
            // Cursor is outside: cancel expand work item
            hoverExpandWorkItem?.cancel()
            hoverExpandWorkItem = nil

            // Graceful exit with debounce: prevents closing while transitioning between tabs with different widths
            if stateModel.isHovering && hoverExitWorkItem == nil {
                let exitWork = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.hoverExitWorkItem = nil

                    guard let scr = NSScreen.main ?? NSScreen.screens.first else { return }
                    let mouseNow = NSEvent.mouseLocation
                    let currentW = self.stateModel.targetWidth
                    let currentH = self.stateModel.targetHeight
                    let currentRect = NSRect(
                        x: scr.frame.midX - currentW / 2.0,
                        y: scr.frame.maxY - currentH,
                        width: currentW,
                        height: currentH
                    )
                    if !currentRect.contains(mouseNow) {
                        if !self.stateModel.isPinnedOpen {
                            self.panel.ignoresMouseEvents = true
                            if self.stateModel.isManuallyCollapsed {
                                self.stateModel.isManuallyCollapsed = false
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                self.stateModel.isHovering = false
                                self.stateModel.isMirrorHovered = false
                            }
                        }
                    }
                }
                hoverExitWorkItem = exitWork
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: exitWork)
            }
        }
    }

    private func setupVisibilitySubscription() {
        stateModel.$isNotchHidden
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in
                guard let self = self else { return }
                if hidden {
                    self.panel.ignoresMouseEvents = true
                    self.panel.orderOut(nil)
                } else {
                    self.positionAtTopCenter()
                    self.panel.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)
    }

    private func setupRingLightSubscription() {
        Publishers.CombineLatest(stateModel.$isRingLightOn, stateModel.$ringLightWarmth)
            .receive(on: DispatchQueue.main)
            .sink { isOn, warmth in
                RingLightWindowController.shared.updateRingLight(isEnabled: isOn, warmth: warmth)
            }
            .store(in: &cancellables)
    }
}
