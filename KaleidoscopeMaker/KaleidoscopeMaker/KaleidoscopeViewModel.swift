import SwiftUI
import UIKit

class KaleidoscopeViewModel: ObservableObject {
    @Published var sourceImage: UIImage? {
        didSet {
            if sourceImage != nil && oldValue !== sourceImage {
                centerX = 0.5
                centerY = 0.5
                zoom = 1.0
                rotation = 0
                segments = 12
                segmentsFloat = 6
            }
            renderKaleidoscope()
        }
    }

    @Published var centerX: Double = 0.5 { didSet { renderKaleidoscope() } }
    @Published var centerY: Double = 0.5 { didSet { renderKaleidoscope() } }
    @Published var segments: Int = 12 { didSet { renderKaleidoscope() } }
    @Published var segmentsFloat: Double = 6
    @Published var zoom: Double = 1.0 { didSet { renderKaleidoscope() } }
    @Published var rotation: Double = 0 { didSet { renderKaleidoscope() } }
    @Published var renderedImage: UIImage?

    private let outputSize: CGFloat = 1080

    func shuffle() {
        centerX = Double.random(in: 0.15...0.85)
        centerY = Double.random(in: 0.15...0.85)
        let segOptions = [6, 8, 10, 12, 16, 20, 24]
        segments = segOptions.randomElement() ?? 12
        segmentsFloat = Double(segments / 2)
        zoom = Double.random(in: 0.5...2.0)
        rotation = Double.random(in: 0...(Double.pi * 2))
    }

    func renderKaleidoscope() {
        guard let source = sourceImage else {
            renderedImage = nil
            return
        }

        let size = outputSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        renderedImage = renderer.image { context in
            let cgCtx = context.cgContext
            let numSegments = segments
            let halfAngle = CGFloat.pi / CGFloat(numSegments)
            let cx = size / 2
            let cy = size / 2
            let radius = size * 0.75

            // Draw source onto temp image centered on chosen point
            let sourceSize = source.size
            let scale = (size / min(sourceSize.width, sourceSize.height)) * zoom
            let drawW = sourceSize.width * scale
            let drawH = sourceSize.height * scale
            let srcCx = sourceSize.width * centerX
            let srcCy = sourceSize.height * centerY
            let drawX = cx - srcCx * scale
            let drawY = cy - srcCy * scale

            let tmpRenderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let tmpImage = tmpRenderer.image { tmpCtx in
                let ctx = tmpCtx.cgContext
                // Apply rotation around center
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -cx, y: -cy)
                source.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
            }

            guard let tmpCGImage = tmpImage.cgImage else { return }

            for i in 0..<numSegments {
                let angle = (2 * CGFloat.pi / CGFloat(numSegments)) * CGFloat(i)
                let mirrored = i % 2 == 1

                cgCtx.saveGState()
                cgCtx.translateBy(x: cx, y: cy)
                cgCtx.rotate(by: angle)

                if mirrored {
                    cgCtx.scaleBy(x: 1, y: -1)
                }

                // Clip to wedge
                cgCtx.beginPath()
                cgCtx.move(to: .zero)
                cgCtx.addLine(to: CGPoint(
                    x: radius * cos(-halfAngle),
                    y: radius * sin(-halfAngle)
                ))
                cgCtx.addArc(
                    center: .zero,
                    radius: radius,
                    startAngle: -halfAngle,
                    endAngle: halfAngle,
                    clockwise: false
                )
                cgCtx.closePath()
                cgCtx.clip()

                // Draw source
                cgCtx.draw(tmpCGImage, in: CGRect(x: -cx, y: -cy, width: size, height: size))

                cgCtx.restoreGState()
            }

            // Circular vignette
            let colors = [
                UIColor.black.withAlphaComponent(0).cgColor,
                UIColor.black.withAlphaComponent(0.3).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.55, 1.0]) {
                cgCtx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: cx, y: cy),
                    startRadius: size * 0.3,
                    endCenter: CGPoint(x: cx, y: cy),
                    endRadius: size * 0.52,
                    options: .drawsAfterEndLocation
                )
            }
        }
    }
}
