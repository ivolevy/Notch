import AppKit
import CoreGraphics
import Foundation

func createContinuousRoundedRectPath(rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let r = min(radius, min(rect.width, rect.height) * 0.5)
    let minX = rect.minX, maxX = rect.maxX
    let minY = rect.minY, maxY = rect.maxY
    let c: CGFloat = r * 0.55228475

    path.move(to: CGPoint(x: minX + r, y: minY))
    path.addLine(to: CGPoint(x: maxX - r, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + r), control1: CGPoint(x: maxX - r + c, y: minY), control2: CGPoint(x: maxX, y: minY + r - c))
    path.addLine(to: CGPoint(x: maxX, y: maxY - r))
    path.addCurve(to: CGPoint(x: maxX - r, y: maxY), control1: CGPoint(x: maxX, y: maxY - r + c), control2: CGPoint(x: maxX - r + c, y: maxY))
    path.addLine(to: CGPoint(x: minX + r, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - r), control1: CGPoint(x: minX + r - c, y: maxY), control2: CGPoint(x: minX, y: maxY - r + c))
    path.addLine(to: CGPoint(x: minX, y: minY + r))
    path.addCurve(to: CGPoint(x: minX + r, y: minY), control1: CGPoint(x: minX, y: minY + r - c), control2: CGPoint(x: minX + r - c, y: minY))
    path.closeSubpath()
    return path
}

/// Builds a single unified Screen path that has rounded outer corners AND the Apple Notch carved out of its top center edge.
func createScreenWithNotchCutoutPath(
    rect: CGRect,
    cornerRadius: CGFloat,
    notchWidth: CGFloat,
    notchHeight: CGFloat,
    topShoulderRadius: CGFloat,
    bottomCornerRadius: CGFloat
) -> CGPath {
    let path = CGMutablePath()
    let r = min(cornerRadius, min(rect.width, rect.height) * 0.5)
    let minX = rect.minX, maxX = rect.maxX
    let minY = rect.minY, maxY = rect.maxY
    let c: CGFloat = r * 0.55228475

    let midX = rect.midX
    let leftX = midX - notchWidth * 0.5
    let rightX = midX + notchWidth * 0.5
    let bottomY = maxY - notchHeight
    let topR = topShoulderRadius
    let botR = bottomCornerRadius

    // Start at bottom-left after corner
    path.move(to: CGPoint(x: minX + r, y: minY))
    // Bottom edge
    path.addLine(to: CGPoint(x: maxX - r, y: minY))
    // Bottom-right corner
    path.addCurve(to: CGPoint(x: maxX, y: minY + r), control1: CGPoint(x: maxX - r + c, y: minY), control2: CGPoint(x: maxX, y: minY + r - c))
    // Right edge
    path.addLine(to: CGPoint(x: maxX, y: maxY - r))
    // Top-right screen corner
    path.addCurve(to: CGPoint(x: maxX - r, y: maxY), control1: CGPoint(x: maxX, y: maxY - r + c), control2: CGPoint(x: maxX - r + c, y: maxY))

    // Top-right horizontal menu bar segment going left to Notch outer right shoulder
    path.addLine(to: CGPoint(x: rightX + topR, y: maxY))
    // Notch top-right concave shoulder curving down
    path.addQuadCurve(to: CGPoint(x: rightX, y: maxY - topR), control: CGPoint(x: rightX, y: maxY))
    // Notch right vertical wall going down
    path.addLine(to: CGPoint(x: rightX, y: bottomY + botR))
    // Notch bottom-right rounded corner
    path.addQuadCurve(to: CGPoint(x: rightX - botR, y: bottomY), control: CGPoint(x: rightX, y: bottomY))
    // Notch bottom horizontal edge going left
    path.addLine(to: CGPoint(x: leftX + botR, y: bottomY))
    // Notch bottom-left rounded corner
    path.addQuadCurve(to: CGPoint(x: leftX, y: bottomY + botR), control: CGPoint(x: leftX, y: bottomY))
    // Notch left vertical wall going up
    path.addLine(to: CGPoint(x: leftX, y: maxY - topR))
    // Notch top-left concave shoulder curving out to top-left horizontal menu bar segment
    path.addQuadCurve(to: CGPoint(x: leftX - topR, y: maxY), control: CGPoint(x: leftX, y: maxY))

    // Top-left horizontal menu bar segment to top-left screen corner
    path.addLine(to: CGPoint(x: minX + r, y: maxY))
    // Top-left screen corner
    path.addCurve(to: CGPoint(x: minX, y: maxY - r), control1: CGPoint(x: minX + r - c, y: maxY), control2: CGPoint(x: minX, y: maxY - r + c))
    // Left edge
    path.addLine(to: CGPoint(x: minX, y: minY + r))
    // Bottom-left screen corner
    path.addCurve(to: CGPoint(x: minX + r, y: minY), control1: CGPoint(x: minX, y: minY + r - c), control2: CGPoint(x: minX + r - c, y: minY))

    path.closeSubpath()
    return path
}

func renderIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let scale = CGFloat(size) / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Outer macOS Squircle (824x824 centered at 512,512)
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircleRadius: CGFloat = 176
    let squirclePath = createContinuousRoundedRectPath(rect: squircleRect, radius: squircleRadius)

    // Apple HIG Drop Shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14 * scale),
        blur: 30 * scale,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.44)
    )
    ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to outer squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Seamless Hardware Bezel + Notch Base (One continuous deep Space-Black surface)
    let bezelColors = [
        CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0),
        CGColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1.0)
    ] as CFArray
    let bezelGrad = CGGradient(colorsSpace: colorSpace, colors: bezelColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        bezelGrad,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )

    // 3. Unified Inner Display Surface with Apple Notch Cutout
    let bezelInset: CGFloat = 36
    let screenRect = squircleRect.insetBy(dx: bezelInset, dy: bezelInset)
    let screenRadius: CGFloat = 140
    let notchW: CGFloat = 368
    let notchH: CGFloat = 154
    let topR: CGFloat = 32
    let botR: CGFloat = 52

    let screenWithNotchPath = createScreenWithNotchCutoutPath(
        rect: screenRect,
        cornerRadius: screenRadius,
        notchWidth: notchW,
        notchHeight: notchH,
        topShoulderRadius: topR,
        bottomCornerRadius: botR
    )

    ctx.saveGState()
    ctx.addPath(screenWithNotchPath)
    ctx.clip()

    // Minimalist Apple Display Gradient (Luminous Ice-Silver at top -> Cool Azure-Slate -> Deep Midnight Indigo)
    let bgColors = [
        CGColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1.0),
        CGColor(red: 0.66, green: 0.78, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.20, green: 0.30, blue: 0.52, alpha: 1.0),
        CGColor(red: 0.09, green: 0.13, blue: 0.25, alpha: 1.0)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.38, 0.78, 1.0])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: 512, y: screenRect.maxY),
        end: CGPoint(x: 512, y: screenRect.minY),
        options: []
    )

    // Soft atmospheric radial glow centered below the Notch (with startRadius: 0 so zero center artifact!)
    let glowColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.60),
        CGColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        glowGrad,
        startCenter: CGPoint(x: 512, y: screenRect.maxY - 190),
        startRadius: 0,
        endCenter: CGPoint(x: 512, y: screenRect.maxY - 220),
        endRadius: 420,
        options: [.drawsBeforeStartLocation]
    )

    // Cast a soft ambient drop shadow from the Notch down onto the screen
    let leftX = 512 - notchW * 0.5
    let rightX = 512 + notchW * 0.5
    let topY = screenRect.maxY
    let bottomY = topY - notchH

    let notchSilhouette = CGMutablePath()
    notchSilhouette.move(to: CGPoint(x: leftX - topR, y: topY + 20))
    notchSilhouette.addLine(to: CGPoint(x: leftX - topR, y: topY))
    notchSilhouette.addQuadCurve(to: CGPoint(x: leftX, y: topY - topR), control: CGPoint(x: leftX, y: topY))
    notchSilhouette.addLine(to: CGPoint(x: leftX, y: bottomY + botR))
    notchSilhouette.addQuadCurve(to: CGPoint(x: leftX + botR, y: bottomY), control: CGPoint(x: leftX, y: bottomY))
    notchSilhouette.addLine(to: CGPoint(x: rightX - botR, y: bottomY))
    notchSilhouette.addQuadCurve(to: CGPoint(x: rightX, y: bottomY + botR), control: CGPoint(x: rightX, y: bottomY))
    notchSilhouette.addLine(to: CGPoint(x: rightX, y: topY - topR))
    notchSilhouette.addQuadCurve(to: CGPoint(x: rightX + topR, y: topY), control: CGPoint(x: rightX, y: topY))
    notchSilhouette.addLine(to: CGPoint(x: rightX + topR, y: topY + 20))
    notchSilhouette.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 22 * scale,
        color: CGColor(red: 0.02, green: 0.06, blue: 0.18, alpha: 0.28)
    )
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
    ctx.addPath(notchSilhouette)
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle crisp inner glass border around the screen + Notch contour
    ctx.saveGState()
    ctx.addPath(screenWithNotchPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35))
    ctx.setLineWidth(3.0)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // End screenWithNotchPath clip

    // 4. Minimalist Apple Camera Lens + Active Green Privacy Dot inside the Notch
    let centerY = bottomY + notchH * 0.48

    // Camera outer sapphire housing
    let lensR: CGFloat = 23
    let lensRect = CGRect(x: 512 - lensR, y: centerY - lensR, width: lensR * 2, height: lensR * 2)
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1.0))
    ctx.fillEllipse(in: lensRect)
    ctx.setStrokeColor(CGColor(red: 0.22, green: 0.27, blue: 0.38, alpha: 0.75))
    ctx.setLineWidth(2.2)
    ctx.strokeEllipse(in: lensRect)

    // Camera inner dark aperture
    let apertureR: CGFloat = 12.5
    ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: 512 - apertureR, y: centerY - apertureR, width: apertureR * 2, height: apertureR * 2))

    // Sapphire blue optical reflection dot
    let glintR: CGFloat = 5.2
    ctx.setFillColor(CGColor(red: 0.32, green: 0.64, blue: 1.0, alpha: 0.88))
    ctx.fillEllipse(in: CGRect(x: 512 - glintR - 2.5, y: centerY - glintR + 2.5, width: glintR * 2, height: glintR * 2))
    ctx.restoreGState()

    // Green privacy indicator dot on the right side of the Notch
    let dotR: CGFloat = 7.2
    let dotCenter = CGPoint(x: 512 + 94, y: centerY)
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 10 * scale,
        color: CGColor(red: 0.18, green: 0.90, blue: 0.46, alpha: 0.85)
    )
    ctx.setFillColor(CGColor(red: 0.22, green: 0.88, blue: 0.46, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2))
    ctx.restoreGState()

    // 5. Outer Squircle Specular Titanium Rim
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20))
    ctx.setLineWidth(3.5)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // End outer squircle clip
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let baseDir = URL(fileURLWithPath: "/Users/ivanlevy/Desktop/DynamicNotch")
let pngRep = renderIcon(size: 1024)
try pngRep.representation(using: .png, properties: [:])!.write(to: baseDir.appendingPathComponent("AppIcon.png"))

// Generate full .iconset for macOS iconutil
let iconsetDir = baseDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let rep = renderIcon(size: spec.pixels)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconsetDir.appendingPathComponent(spec.name))
}
print("Generated AppIcon.png and AppIcon.iconset")
