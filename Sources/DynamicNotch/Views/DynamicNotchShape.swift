import SwiftUI

/// Minimalist Apple-style Notch shape flush with the top edge of the screen.
/// Stays strictly inside `rect` so `.clipShape` and `.stroke` never overflow or clip.
struct DynamicNotchShape: Shape {
    var bottomCornerRadius: CGFloat = 14
    var topShoulderRadius: CGFloat = 6

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomCornerRadius, topShoulderRadius) }
        set {
            bottomCornerRadius = newValue.first
            topShoulderRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topR = min(topShoulderRadius, rect.height * 0.25)
        let botR = min(bottomCornerRadius, (rect.height - topR) * 0.5)
        let leftX = rect.minX + topR
        let rightX = rect.maxX - topR
        let bottomY = rect.maxY - 0.5

        // Start at top-left outer shoulder (flush with top of screen y = 0)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left smooth shoulder curving down into the left vertical wall
        path.addQuadCurve(
            to: CGPoint(x: leftX, y: rect.minY + topR),
            control: CGPoint(x: leftX, y: rect.minY)
        )

        // Left vertical edge down to bottom-left corner
        path.addLine(to: CGPoint(x: leftX, y: bottomY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: leftX + botR, y: bottomY),
            control: CGPoint(x: leftX, y: bottomY)
        )

        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: rightX - botR, y: bottomY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rightX, y: bottomY - botR),
            control: CGPoint(x: rightX, y: bottomY)
        )

        // Right vertical edge up to top-right shoulder
        path.addLine(to: CGPoint(x: rightX, y: rect.minY + topR))

        // Top-right smooth shoulder curving out to top edge
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rightX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
