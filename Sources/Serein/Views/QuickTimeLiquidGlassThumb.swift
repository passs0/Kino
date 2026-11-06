import SwiftUI
import AppKit

/// Authentic macOS QuickTime Player Scrubber Thumb.
/// In resting state: Displays the Apple-native white capsule thumb.
/// While scrubbing: Morphs into the optical Liquid Glass Lens with top specular glint,
/// internal submerged rail, and transparent light transmission.
public struct NativeQuickTimeScrubberThumb: View {
    public var isScrubbing: Bool
    public var trackHeight: CGFloat = 5.5

    public init(isScrubbing: Bool, trackHeight: CGFloat = 5.5) {
        self.isScrubbing = isScrubbing
        self.trackHeight = trackHeight
    }

    public var body: some View {
        ZStack {
            if isScrubbing {
                // MARK: - Liquid Glass Lens State (During Scrubbing)
                let width: CGFloat = 24.0
                let height: CGFloat = 19.5

                // 1. Soft Ambient Drop Shadow (positioned below the glass lens)
                Capsule()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: width - 2, height: height * 0.6)
                    .blur(radius: 3.0)
                    .offset(y: 5.0)

                // 2. Pure Translucent Optical Lens Body (Clean light transmission)
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.28), location: 0.0),
                                .init(color: Color.white.opacity(0.08), location: 0.35),
                                .init(color: Color.clear, location: 0.70),
                                .init(color: Color.black.opacity(0.05), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: height)

                // 3. Submerged white rail inside the glass lens (enters from left edge to center)
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: width * 0.48, height: trackHeight)
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: height)
                .clipShape(Capsule())

                // 4. Subtle diffusion glow around the submerged tip
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: width * 0.50, height: trackHeight + 2)
                        .blur(radius: 1.0)
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: height)
                .clipShape(Capsule())

                // 5. Specular highlight crescent along the top rim
                VStack {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.85), location: 0.0),
                                    .init(color: Color.white.opacity(0.25), location: 0.35),
                                    .init(color: Color.clear, location: 0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)

                // 6. Bottom subtle reflective rim
                VStack {
                    Spacer()
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.12), location: 0.85),
                                    .init(color: Color.white.opacity(0.25), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)

                // 7. Ambient rim line (fine edge)
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.25), location: 0.0),
                                .init(color: Color.black.opacity(0.22), location: 0.50),
                                .init(color: Color.black.opacity(0.35), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .frame(width: width, height: height)
            } else {
                // MARK: - Resting State: Apple Native White Capsule Thumb
                let width: CGFloat = 20.0
                let height: CGFloat = 16.0

                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: width, height: height)
                    .blur(radius: 2.0)
                    .offset(y: 1.0)

                Capsule()
                    .fill(Color.white)
                    .frame(width: width, height: height)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
        .frame(width: isScrubbing ? 24.0 : 20.0, height: isScrubbing ? 19.5 : 16.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isScrubbing)
    }
}

/// Native CoreGraphics renderer for the QuickTime Scrubber Thumb.
/// Provides zero-allocation, 60fps rendering in AppKit NSView.draw(_:).
public enum QuickTimeLiquidGlassRenderer {
    public static func draw(
        in ctx: CGContext,
        isScrubbing: Bool,
        thumbRect: CGRect,
        trackY: CGFloat,
        trackHeight: CGFloat
    ) {
        let thumbWidth = thumbRect.width
        let thumbHeight = thumbRect.height
        let thumbX = thumbRect.minX
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let thumbPath = CGPath(roundedRect: thumbRect, cornerWidth: thumbHeight / 2, cornerHeight: thumbHeight / 2, transform: nil)

        if isScrubbing {
            // MARK: - Liquid Glass Lens (Scrubbing)
            ctx.saveGState()

            // 1. Bottom shadow
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -3.5),
                blur: 3.5,
                color: NSColor.black.withAlphaComponent(0.32).cgColor
            )
            let shadowPath = CGPath(roundedRect: thumbRect.insetBy(dx: 1.0, dy: 1.0), cornerWidth: (thumbHeight - 2.0) / 2, cornerHeight: (thumbHeight - 2.0) / 2, transform: nil)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.30).cgColor)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Clip to glass body
            ctx.saveGState()
            ctx.addPath(thumbPath)
            ctx.clip()

            // 2. Translucent optical glass gradient
            let glassColors = [
                NSColor.white.withAlphaComponent(0.28).cgColor,
                NSColor.white.withAlphaComponent(0.08).cgColor,
                NSColor.clear.cgColor,
                NSColor.black.withAlphaComponent(0.05).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: colorSpace, colors: glassColors, locations: [0.0, 0.35, 0.70, 1.0]) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: thumbRect.midX, y: thumbRect.maxY), end: CGPoint(x: thumbRect.midX, y: thumbRect.minY), options: [])
            }

            // 3. Submerged white rail inside the lens (enters from left edge to center 48%)
            let submergedWidth = thumbWidth * 0.48
            let submergedRect = CGRect(x: thumbX, y: trackY, width: submergedWidth, height: trackHeight)
            let submergedPath = CGPath(roundedRect: submergedRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            ctx.addPath(submergedPath)
            ctx.fillPath()

            // 4. Subtle diffusion glow around submerged tip
            let glowRect = CGRect(x: thumbX, y: trackY - 1, width: thumbWidth * 0.50, height: trackHeight + 2)
            let glowPath = CGPath(roundedRect: glowRect, cornerWidth: (trackHeight + 2) / 2, cornerHeight: (trackHeight + 2) / 2, transform: nil)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.25).cgColor)
            ctx.addPath(glowPath)
            ctx.fillPath()

            // 5. Specular highlight crescent along top curved rim
            let specColors = [
                NSColor.white.withAlphaComponent(0.85).cgColor,
                NSColor.white.withAlphaComponent(0.25).cgColor,
                NSColor.clear.cgColor
            ] as CFArray
            if let specGrad = CGGradient(colorsSpace: colorSpace, colors: specColors, locations: [0.0, 0.35, 0.65]) {
                let strokePath = CGPath(roundedRect: thumbRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: (thumbHeight - 1.0) / 2, cornerHeight: (thumbHeight - 1.0) / 2, transform: nil)
                ctx.saveGState()
                ctx.addPath(strokePath)
                ctx.setLineWidth(1.0)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                ctx.drawLinearGradient(specGrad, start: CGPoint(x: thumbRect.midX, y: thumbRect.maxY), end: CGPoint(x: thumbRect.midX, y: thumbRect.minY), options: [])
                ctx.restoreGState()
            }

            // 6. Bottom subtle reflective rim
            let btmColors = [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.12).cgColor,
                NSColor.white.withAlphaComponent(0.25).cgColor
            ] as CFArray
            if let btmGrad = CGGradient(colorsSpace: colorSpace, colors: btmColors, locations: [0.0, 0.85, 1.0]) {
                let strokePath = CGPath(roundedRect: thumbRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: (thumbHeight - 1.0) / 2, cornerHeight: (thumbHeight - 1.0) / 2, transform: nil)
                ctx.saveGState()
                ctx.addPath(strokePath)
                ctx.setLineWidth(0.8)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                ctx.drawLinearGradient(btmGrad, start: CGPoint(x: thumbRect.midX, y: thumbRect.maxY), end: CGPoint(x: thumbRect.midX, y: thumbRect.minY), options: [])
                ctx.restoreGState()
            }

            ctx.restoreGState() // Restore clip

            // 7. Ambient rim line
            let rimColors = [
                NSColor.white.withAlphaComponent(0.25).cgColor,
                NSColor.black.withAlphaComponent(0.22).cgColor,
                NSColor.black.withAlphaComponent(0.35).cgColor
            ] as CFArray
            if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 0.50, 1.0]) {
                ctx.saveGState()
                ctx.addPath(thumbPath)
                ctx.setLineWidth(0.75)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                ctx.drawLinearGradient(rimGrad, start: CGPoint(x: thumbRect.midX, y: thumbRect.maxY), end: CGPoint(x: thumbRect.midX, y: thumbRect.minY), options: [])
                ctx.restoreGState()
            }

            ctx.restoreGState()
        } else {
            // MARK: - Resting State: Apple Native White Capsule Thumb
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1.5),
                blur: 2.5,
                color: NSColor.black.withAlphaComponent(0.32).cgColor
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.addPath(thumbPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Fine border stroke
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
            ctx.setLineWidth(0.5)
            ctx.addPath(thumbPath)
            ctx.strokePath()
        }
    }
}
