import SwiftUI
import AppKit

/// Vector silhouette of the HUAWEI FreeClip C-bridge earbud (comfort bean, acoustic ball, and arch).
struct FreeClipIconView: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let s = min(w, h)
            let dx = (w - s) / 2
            let dy = (h - s) / 2
            let stroke = max(1.3, s * 0.105)

            ZStack {
                // C-bridge arch connecting the comfort bean and acoustic ball
                Path { path in
                    path.move(to: CGPoint(x: dx + s * 0.36, y: dy + s * 0.50))
                    path.addCurve(
                        to: CGPoint(x: dx + s * 0.70, y: dy + s * 0.52),
                        control1: CGPoint(x: dx + s * 0.34, y: dy + s * 0.14),
                        control2: CGPoint(x: dx + s * 0.72, y: dy + s * 0.14)
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: stroke * 1.15, lineCap: .round))

                // Comfort bean (left)
                Ellipse()
                    .stroke(lineWidth: stroke)
                    .frame(width: s * 0.46, height: s * 0.34)
                    .position(x: dx + s * 0.35, y: dy + s * 0.66)

                // Acoustic ball (right, clean cutout over arch)
                Circle()
                    .frame(width: s * 0.36, height: s * 0.36)
                    .position(x: dx + s * 0.68, y: dy + s * 0.67)
                    .blendMode(.destinationOut)
                Circle()
                    .stroke(lineWidth: stroke)
                    .frame(width: s * 0.36, height: s * 0.36)
                    .position(x: dx + s * 0.68, y: dy + s * 0.67)
            }
            .compositingGroup()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

enum FreeClipStatusIcon {
    static func templateImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let s = min(rect.width, rect.height)
            let dx = (rect.width - s) / 2
            let dy = (rect.height - s) / 2
            let stroke = max(1.4, s * 0.105)

            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            // C-bridge arch
            let arch = NSBezierPath()
            arch.lineWidth = stroke * 1.15
            arch.lineCapStyle = .round
            arch.move(to: NSPoint(x: dx + s * 0.36, y: dy + s * 0.48))
            arch.curve(
                to: NSPoint(x: dx + s * 0.70, y: dy + s * 0.50),
                controlPoint1: NSPoint(x: dx + s * 0.34, y: dy + s * 0.12),
                controlPoint2: NSPoint(x: dx + s * 0.72, y: dy + s * 0.12)
            )
            arch.stroke()

            // Comfort bean (left)
            let beanRect = NSRect(
                x: dx + s * 0.12,
                y: dy + s * 0.49,
                width: s * 0.46,
                height: s * 0.34
            )
            let bean = NSBezierPath(ovalIn: beanRect)
            bean.lineWidth = stroke
            bean.stroke()

            // Acoustic ball (right, clear interior then stroke)
            let ballRect = NSRect(
                x: dx + s * 0.50,
                y: dy + s * 0.49,
                width: s * 0.36,
                height: s * 0.36
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: ballRect).fill()
            NSGraphicsContext.restoreGraphicsState()

            let ball = NSBezierPath(ovalIn: ballRect)
            ball.lineWidth = stroke
            ball.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
