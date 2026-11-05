import AppKit

let args = CommandLine.arguments
let srcPath = args.count > 1 ? args[1] : "assets/icon.png"
let outMaster = args.count > 2 ? args[2] : "assets/icon.png"
let outIcns = args.count > 3 ? args[3] : "Resources/AppIcon.icns"

func renderMacIcon(srcPath: String, outMaster: String, outIcns: String) throws {
    let srcURL = URL(fileURLWithPath: srcPath)
    guard let srcImg = NSImage(contentsOf: srcURL),
          let cgImage = srcImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Could not load source image from \(srcPath)")
    }

    let size: CGFloat = 1024
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS native dock drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 24,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.40)
    )

    let bodySize: CGFloat = 824
    let margin: CGFloat = (size - bodySize) / 2.0 // 100 pt margin
    let bodyRect = CGRect(x: margin, y: margin + 4, width: bodySize, height: bodySize)

    ctx.draw(cgImage, in: bodyRect)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    guard let masterPNG = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode master PNG")
    }

    try masterPNG.write(to: URL(fileURLWithPath: outMaster))
    print("✅ Master macOS icon written to \(outMaster)")

    // Generate iconset
    let tempIconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Serein_\(UUID().uuidString).iconset")
    let fm = FileManager.default
    try fm.createDirectory(at: tempIconset, withIntermediateDirectories: true)

    let masterImage = NSImage(data: masterPNG)!
    let targets: [(String, Int)] = [
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

    for (filename, px) in targets {
        let targetRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        let tNsCtx = NSGraphicsContext(bitmapImageRep: targetRep)!
        NSGraphicsContext.current = tNsCtx
        let tCtx = tNsCtx.cgContext
        tCtx.setAllowsAntialiasing(true)
        tCtx.setShouldAntialias(true)
        tCtx.interpolationQuality = .high

        masterImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let data = targetRep.representation(using: .png, properties: [:])!
        let outURL = tempIconset.appendingPathComponent(filename)
        try data.write(to: outURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", tempIconset.path, "-o", outIcns]
    try process.run()
    process.waitUntilExit()

    try? fm.removeItem(at: tempIconset)

    if process.terminationStatus == 0 {
        print("✅ AppIcon.icns written to \(outIcns)")
    } else {
        fatalError("iconutil failed with code \(process.terminationStatus)")
    }
}

try renderMacIcon(srcPath: srcPath, outMaster: outMaster, outIcns: outIcns)
