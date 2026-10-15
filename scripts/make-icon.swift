import AppKit

// Builds the app icon at every size an .icns needs: the Android Hub glyph on a macOS-style rounded-square plate.
// usage: swift make-icon.swift <glyph.png> <output.iconset directory>
//
// The glyph (scripts/assets/AppIconGlyph.png) is a transparent PNG; the plate, shadow and padding follow Apple's
// 1024-pt icon grid (824-pt body, 100-pt margin, ~22% corner radius).

guard CommandLine.arguments.count == 3, let glyph = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <glyph.png> <output.iconset>\n".utf8))
    exit(1)
}

func render(size: Int) -> Data {
    let canvas = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let body = canvas * 824 / 1024
    let plate = NSRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)
    let path = NSBezierPath(roundedRect: plate, xRadius: body * 0.2237, yRadius: body * 0.2237)

    // Soft drop shadow under the plate.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = canvas * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.01)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Plate: white with a faint cool gradient toward the bottom.
    NSGradient(colors: [NSColor.white, NSColor(red: 0.91, green: 0.95, blue: 0.93, alpha: 1)])!.draw(in: path, angle: -90)

    // Glyph, centred, ~66% of the plate height.
    let glyphHeight = body * 0.66
    let glyphWidth = glyphHeight * glyph.size.width / glyph.size.height
    let glyphRect = NSRect(
        x: plate.midX - glyphWidth / 2, y: plate.midY - glyphHeight / 2, width: glyphWidth, height: glyphHeight)
    glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

    return bitmap.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes { try render(size: size).write(to: output.appendingPathComponent("\(name).png")) }
