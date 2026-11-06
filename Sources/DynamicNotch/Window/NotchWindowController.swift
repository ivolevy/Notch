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

        let initialRect = NSRect(x: 0, y: 0, width: canvasWidth, height: 28)
        self.panel = NotchPanel(contentRect: initialRect)

        let rootView = DynamicNotchView(
            stateModel: stateModel,
            nowPlaying: nowPlayingService,
            cameraService: cameraService
        )

        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
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
        setupFrameSubscription()
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
        let w = max(stateModel.targetWidth + 32, 440)
        let h = max(stateModel.targetHeight + 4, 28)
        let x = screenFrame.midX - (w / 2.0)
        let y = screenFrame.maxY - h
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    private func updatePanelFrame() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.frame
        let w = max(stateModel.targetWidth + 32, 440)
        let h = max(stateModel.targetHeight + 4, 28)
        let newX = screenFrame.midX - (w / 2.0)
        let newY = screenFrame.maxY - h
        let newFrame = NSRect(x: newX, y: newY, width: w, height: h)
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func setupFrameSubscription() {
        stateModel.$isHovering
            .combineLatest(stateModel.$isPinnedOpen, stateModel.$activeTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelFrame()
            }
            .store(in: &cancellables)
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

        let isDirectlyOverNotch = notchScreenRect.contains(mouseLoc)

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
                    self.updatePanelFrame()
                }
            }
            return
        }

        if isDirectlyOverNotch {
            // Cursor is strictly inside the visible notch silhouette: capture mouse events
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }

            hoverExitWorkItem?.cancel()
            hoverExitWorkItem = nil

            if stateModel.isManuallyCollapsed {
                return
            }

            // Immediately switch tabs on hover when expanded
            if stateModel.isHovering || stateModel.isPinnedOpen {
                let notchLeft = screenFrame.midX - (activeW / 2.0)
                let tabTopY = screenFrame.maxY - 4
                let tabBottomY = screenFrame.maxY - 36

                if mouseLoc.y >= tabBottomY && mouseLoc.y <= tabTopY {
                    if mouseLoc.x >= (notchLeft + 14) && mouseLoc.x < (notchLeft + 45) {
                        stateModel.switchTabOnHover(.music)
                    } else if mouseLoc.x >= (notchLeft + 45) && mouseLoc.x < (notchLeft + 75) {
                        stateModel.switchTabOnHover(.tray)
                    } else if mouseLoc.x >= (notchLeft + 75) && mouseLoc.x <= (notchLeft + 112) {
                        stateModel.switchTabOnHover(.camera)
                    }
                }
            }

            if !stateModel.isHovering && hoverExpandWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.hoverExpandWorkItem = nil
                    guard !self.stateModel.isNotchHidden && !self.stateModel.isManuallyCollapsed else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        self.stateModel.isHovering = true
                    }
                    self.updatePanelFrame()
                }
                hoverExpandWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
        } else {
            // Cursor is OUTSIDE the visible notch: ALWAYS pass mouse events through to Safari/underlying apps!
            if !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
            }

            hoverExpandWorkItem?.cancel()
            hoverExpandWorkItem = nil

            // If expanded and not pinned: exit hover
            if stateModel.isHovering && !stateModel.isPinnedOpen {
                // If moving down towards Safari tabs, collapse immediately!
                if mouseLoc.y < screenFrame.maxY - activeH {
                    hoverExitWorkItem?.cancel()
                    hoverExitWorkItem = nil
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        self.stateModel.isHovering = false
                        self.stateModel.isMirrorHovered = false
                    }
                    self.updatePanelFrame()
                } else if hoverExitWorkItem == nil {
                    // Small horizontal grace period
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
                        if !currentRect.contains(mouseNow) && !self.stateModel.isPinnedOpen {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                self.stateModel.isHovering = false
                                self.stateModel.isMirrorHovered = false
                            }
                            self.updatePanelFrame()
                        }
                    }
                    hoverExitWorkItem = exitWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: exitWork)
                }
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
