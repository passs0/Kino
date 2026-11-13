import AppKit
import CoreGraphics
import CoreText

let args = CommandLine.arguments
let bgImagePath = args.count > 1 ? args[1] : "assets/bg_sample.png"
let outputPath = args.count > 2 ? args[2] : "assets/preview.png"

guard let bgImage = NSImage(contentsOfFile: bgImagePath) else {
    print("❌ Could not load background image from \(bgImagePath)")
    exit(1)
}

let canvasWidth: CGFloat = 1600
let canvasHeight: CGFloat = 1000
let winWidth: CGFloat = 1360
let winHeight: CGFloat = 765
let winX: CGFloat = (canvasWidth - winWidth) / 2.0
let winY: CGFloat = (canvasHeight - winHeight) / 2.0 + 10

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvasWidth),
    height: Int(canvasHeight),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ Failed to create CGContext")
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

let winRect = CGRect(x: winX, y: winY, width: winWidth, height: winHeight)
let cornerRadius: CGFloat = 26.0

// 1. Draw macOS Window Deep Drop Shadow
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -24),
    blur: 60,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.68)
)
let shadowPath = CGPath(roundedRect: winRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
context.addPath(shadowPath)
context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
context.fillPath()
context.restoreGState()

// 2. Secondary ambient shadow
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -4),
    blur: 16,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38)
)
context.addPath(shadowPath)
context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
context.fillPath()
context.restoreGState()

// 3. Clip to Window Continuous Squircle Shape
context.saveGState()
context.addPath(shadowPath)
context.clip()

// 4. Draw Movie Frame
if let cgBg = bgImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    context.draw(cgBg, in: winRect)
}

// 5. Subtle Titlebar Vignette
let titleColors = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.60),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.20),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)
] as CFArray
if let titleGradient = CGGradient(colorsSpace: colorSpace, colors: titleColors, locations: [0.0, 0.45, 1.0]) {
    let topBarRect = CGRect(x: winX, y: winRect.maxY - 75, width: winWidth, height: 75)
    context.saveGState()
    context.clip(to: topBarRect)
    context.drawLinearGradient(
        titleGradient,
        start: CGPoint(x: winX, y: winRect.maxY),
        end: CGPoint(x: winX, y: winRect.maxY - 75),
        options: []
    )
    context.restoreGState()
}

// Bottom HUD subtle shadow vignette
let bottomGradientColors = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.55),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.15),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)
] as CFArray
if let botGradient = CGGradient(colorsSpace: colorSpace, colors: bottomGradientColors, locations: [0.0, 0.55, 1.0]) {
    let botBarRect = CGRect(x: winX, y: winY, width: winWidth, height: 130)
    context.saveGState()
    context.clip(to: botBarRect)
    context.drawLinearGradient(
        botGradient,
        start: CGPoint(x: winX, y: winY),
        end: CGPoint(x: winX, y: winY + 130),
        options: []
    )
    context.restoreGState()
}

// 6. Draw macOS Traffic Lights
let tlY = winRect.maxY - 24
let tlRadius: CGFloat = 6.0
let tlSpacing: CGFloat = 20.0
let tlStartX = winX + 24.0

let lights: [(color: CGColor, border: CGColor)] = [
    (CGColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1.0), CGColor(red: 0.88, green: 0.27, blue: 0.24, alpha: 1.0)), // Red
    (CGColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0), CGColor(red: 0.87, green: 0.63, blue: 0.14, alpha: 1.0)), // Yellow
    (CGColor(red: 0.15, green: 0.79, blue: 0.25, alpha: 1.0), CGColor(red: 0.10, green: 0.67, blue: 0.16, alpha: 1.0))  // Green
]

for (i, l) in lights.enumerated() {
    let center = CGPoint(x: tlStartX + CGFloat(i) * tlSpacing, y: tlY)
    let r = CGRect(x: center.x - tlRadius, y: center.y - tlRadius, width: tlRadius * 2, height: tlRadius * 2)
    context.setFillColor(l.color)
    context.fillEllipse(in: r)
    context.setStrokeColor(l.border)
    context.setLineWidth(0.6)
    context.strokeEllipse(in: r)
}

// 7. Draw Window Title: "Kino — Your Name (2016) • 4K HDR • 5.1"
let titleFont = CTFontCreateWithName("SFProText-Semibold" as CFString, 13.0, nil)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(white: 0.94, alpha: 0.95)
]
let titleStr = NSAttributedString(string: "Kino — Your Name (2016) • 4K HDR • 5.1", attributes: titleAttrs)
let line = CTLineCreateWithAttributedString(titleStr)
let bounds = CTLineGetBoundsWithOptions(line, [])
let titleX = winX + (winWidth - bounds.width) / 2.0
let titleY = tlY - bounds.height / 2.0 - 0.5

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
context.textPosition = CGPoint(x: titleX, y: titleY)
CTLineDraw(line, context)
context.restoreGState()

// 8. Draw Subtitle Cue with Apple MediaAccessibility styling
let subFont = CTFontCreateWithName("SFProDisplay-Medium" as CFString, 21.0, nil)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(white: 0.98, alpha: 0.98)
]
let subStr = NSAttributedString(string: "I feel like I've been searching for someone, ever since that day...", attributes: subAttrs)
let subLine = CTLineCreateWithAttributedString(subStr)
let subBounds = CTLineGetBoundsWithOptions(subLine, [])
let subX = winX + (winWidth - subBounds.width) / 2.0
let subY = winY + 95.0

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 6, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.90))
context.textPosition = CGPoint(x: subX, y: subY)
CTLineDraw(subLine, context)
context.restoreGState()

// 9. Draw Floating Apple Liquid Glass HUD Bar
let hudWidth: CGFloat = 654
let hudHeight: CGFloat = 48
let hudCorner: CGFloat = 24
let hudX = winX + (winWidth - hudWidth) / 2.0
let hudY = winY + 28
let hudRect = CGRect(x: hudX, y: hudY, width: hudWidth, height: hudHeight)
let hudPath = CGPath(roundedRect: hudRect, cornerWidth: hudCorner, cornerHeight: hudCorner, transform: nil)

// HUD Drop Shadow
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -8),
    blur: 26,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
)
context.addPath(hudPath)
context.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.88))
context.fillPath()
context.restoreGState()

// HUD Top Highlight & Glass Stroke
context.saveGState()
context.addPath(hudPath)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
context.setLineWidth(0.8)
context.strokePath()
context.restoreGState()

// Helper to draw SF Symbols in pure white using mask
func drawSFSymbol(name: String, pointSize: CGFloat, x: CGFloat, y: CGFloat, alpha: CGFloat = 0.92) {
    let conf = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(conf) else { return }
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let s = img.size
    let r = CGRect(x: x - s.width / 2.0, y: y - s.height / 2.0, width: s.width, height: s.height)
    context.saveGState()
    context.clip(to: r, mask: cg)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    context.fill(r)
    context.restoreGState()
}

let midY = hudY + hudHeight / 2.0

// Transport Controls (Left): [Rewind 10] [Pause] [Forward 10]
drawSFSymbol(name: "gobackward.10", pointSize: 13.5, x: hudX + 32, y: midY, alpha: 0.92)
drawSFSymbol(name: "pause.fill", pointSize: 16.5, x: hudX + 66, y: midY, alpha: 1.0)
drawSFSymbol(name: "goforward.10", pointSize: 13.5, x: hudX + 100, y: midY, alpha: 0.92)

// Divider 1
let divColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
context.setFillColor(divColor)
context.fill(CGRect(x: hudX + 120, y: midY - 9, width: 1, height: 18))

// Scrubber Bar Group
let timeFont = CTFontCreateWithName("SFProText-Medium" as CFString, 11.0, nil)
let timeAttrs: [NSAttributedString.Key: Any] = [
    .font: timeFont,
    .foregroundColor: NSColor(white: 0.94, alpha: 0.90)
]
let elapsedStr = NSAttributedString(string: "01:24:18", attributes: timeAttrs)
let elapsedLine = CTLineCreateWithAttributedString(elapsedStr)
context.textPosition = CGPoint(x: hudX + 130, y: midY - 4)
CTLineDraw(elapsedLine, context)

// Scrubber slider track
let trackX = hudX + 185
let trackWidth: CGFloat = 135
let trackY = midY - 2
let trackHeight: CGFloat = 4
let trackPath = CGPath(roundedRect: CGRect(x: trackX, y: trackY, width: trackWidth, height: trackHeight), cornerWidth: 2, cornerHeight: 2, transform: nil)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
context.addPath(trackPath)
context.fillPath()

// Filled track
let fillWidth = trackWidth * 0.64
let filledPath = CGPath(roundedRect: CGRect(x: trackX, y: trackY, width: fillWidth, height: trackHeight), cornerWidth: 2, cornerHeight: 2, transform: nil)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
context.addPath(filledPath)
context.fillPath()

// Scrubber Thumb
let thumbCenter = CGPoint(x: trackX + fillWidth, y: midY)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
context.fillEllipse(in: CGRect(x: thumbCenter.x - 5.5, y: thumbCenter.y - 5.5, width: 11, height: 11))
context.restoreGState()

// Remaining time
let remStr = NSAttributedString(string: "-00:42:15", attributes: timeAttrs)
let remLine = CTLineCreateWithAttributedString(remStr)
context.textPosition = CGPoint(x: trackX + trackWidth + 10, y: midY - 4)
CTLineDraw(remLine, context)

// Divider 2
context.setFillColor(divColor)
context.fill(CGRect(x: hudX + 392, y: midY - 9, width: 1, height: 18))

// Volume Group
drawSFSymbol(name: "speaker.wave.2.fill", pointSize: 12.5, x: hudX + 412, y: midY, alpha: 0.92)
let volTrackX = hudX + 430
let volTrackWidth: CGFloat = 46
let volTrackPath = CGPath(roundedRect: CGRect(x: volTrackX, y: trackY, width: volTrackWidth, height: trackHeight), cornerWidth: 2, cornerHeight: 2, transform: nil)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
context.addPath(volTrackPath)
context.fillPath()

let volFillWidth = volTrackWidth * 0.78
let volFilledPath = CGPath(roundedRect: CGRect(x: volTrackX, y: trackY, width: volFillWidth, height: trackHeight), cornerWidth: 2, cornerHeight: 2, transform: nil)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
context.addPath(volFilledPath)
context.fillPath()

let volThumbCenter = CGPoint(x: volTrackX + volFillWidth, y: midY)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
context.fillEllipse(in: CGRect(x: volThumbCenter.x - 4.5, y: volThumbCenter.y - 4.5, width: 9, height: 9))

// Divider 3
context.setFillColor(divColor)
context.fill(CGRect(x: hudX + 494, y: midY - 9, width: 1, height: 18))

// Right Group: [Speed Button 1×] [quote.bubble] [pip] [AirPlay] [Fullscreen]
// 1× Speed pill button
let speedPillRect = CGRect(x: hudX + 506, y: midY - 11, width: 28, height: 22)
let speedPath = CGPath(roundedRect: speedPillRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
context.addPath(speedPath)
context.fillPath()
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
context.setLineWidth(0.5)
context.addPath(speedPath)
context.strokePath()

let speedFont = CTFontCreateWithName("SFProRounded-Semibold" as CFString, 11.0, nil)
let speedAttrs: [NSAttributedString.Key: Any] = [
    .font: speedFont,
    .foregroundColor: NSColor(white: 0.98, alpha: 0.96)
]
let speedStr = NSAttributedString(string: "1×", attributes: speedAttrs)
let speedLine = CTLineCreateWithAttributedString(speedStr)
let speedBounds = CTLineGetBoundsWithOptions(speedLine, [])
context.textPosition = CGPoint(x: speedPillRect.midX - speedBounds.width / 2.0, y: midY - speedBounds.height / 2.0 + 1)
CTLineDraw(speedLine, context)

// Other icons
drawSFSymbol(name: "quote.bubble", pointSize: 13, x: hudX + 554, y: midY, alpha: 0.92)
drawSFSymbol(name: "pip.enter", pointSize: 12.5, x: hudX + 582, y: midY, alpha: 0.92)
drawSFSymbol(name: "airplayvideo", pointSize: 12.5, x: hudX + 610, y: midY, alpha: 0.92)
drawSFSymbol(name: "arrow.up.left.and.arrow.down.right", pointSize: 12, x: hudX + 636, y: midY, alpha: 0.92)

// End of Window Drawing
context.restoreGState()

// 10. Outer Window Border Stroke (Liquid Glass subtle perimeter highlight)
context.saveGState()
context.addPath(shadowPath)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
context.setLineWidth(1.0)
context.strokePath()
context.restoreGState()

guard let outputCGImage = context.makeImage() else {
    print("❌ Failed to create output CGImage")
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: outputCGImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("❌ Failed to encode PNG")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ Beautiful Kino preview image written to \(outputPath)")
