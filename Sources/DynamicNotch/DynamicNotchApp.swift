import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notchWindowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var toggleVisibilityMenuItem: NSMenuItem?
    private var pinMenuItem: NSMenuItem?
    private let stateModel = NotchStateModel()
    private let nowPlayingService = NowPlayingService()
    private let cameraService = CameraMirrorService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load minimalist Apple Notch app icon
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        // Run as accessory/UIElement app without Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupStatusBarItem()

        let controller = NotchWindowController(
            stateModel: stateModel,
            nowPlayingService: nowPlayingService,
            cameraService: cameraService
        )
        controller.show()
        self.notchWindowController = controller
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeNotchMenuBarIcon()
            button.toolTip = "Notch"
        }

        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: "Ocultar Notch",
            action: #selector(toggleNotchVisibility),
            keyEquivalent: "h"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.toggleVisibilityMenuItem = toggleItem

        let pinItem = NSMenuItem(
            title: "Anclar Notch",
            action: #selector(togglePinNotchAction),
            keyEquivalent: "p"
        )
        pinItem.target = self
        menu.addItem(pinItem)
        self.pinMenuItem = pinItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Cerrar Notch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleVisibilityMenuItem?.title = stateModel.isNotchHidden ? "Mostrar Notch" : "Ocultar Notch"
        pinMenuItem?.title = stateModel.isPinnedOpen ? "Desanclar Notch" : "Anclar Notch"
    }

    @objc private func toggleNotchVisibility() {
        stateModel.isNotchHidden.toggle()
        if !stateModel.isNotchHidden {
            stateModel.isManuallyCollapsed = false
        }
    }

    @objc private func togglePinNotchAction() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            stateModel.isPinnedOpen.toggle()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeNotchMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Outer screen top frame
            let frameRect = NSRect(x: 1, y: 2, width: 16, height: 10)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 2.5, yRadius: 2.5)
            framePath.lineWidth = 1.4
            framePath.stroke()

            // Minimalist Apple Notch cutout at top center
            let notchRect = NSRect(x: 5, y: 8.2, width: 8, height: 4.0)
            let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: 1.5, yRadius: 1.5)
            notchPath.fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraService.stopCamera()
        RingLightWindowController.shared.updateRingLight(isEnabled: false, warmth: 0.3)
    }
}

@main
struct DynamicNotchMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
