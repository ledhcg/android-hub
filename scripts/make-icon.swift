import AppKit

// Draws the app icon (a phone mirrored onto a screen) at every size an .icns needs.
// usage: swift make-icon.swift <output.iconset directory>

func render(size: Int) -> Data {
    let scale = CGFloat(size)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: scale, height: scale)

    // Rounded-square background with a diagonal gradient (teal → green).
    let plate = NSBezierPath(roundedRect: rect.insetBy(dx: scale * 0.06, dy: scale * 0.06), xRadius: scale * 0.22, yRadius: scale * 0.22)
    NSGradient(colors: [NSColor(red: 0.04, green: 0.43, blue: 0.55, alpha: 1), NSColor(red: 0.24, green: 0.78, blue: 0.45, alpha: 1)])!
        .draw(in: plate, angle: -50)

    // Phone body.
    let phone = NSRect(x: scale * 0.33, y: scale * 0.2, width: scale * 0.34, height: scale * 0.6)
    let body = NSBezierPath(roundedRect: phone, xRadius: scale * 0.06, yRadius: scale * 0.06)
    NSColor.white.setFill()
    body.fill()
    // Screen.
    let screen = phone.insetBy(dx: scale * 0.022, dy: scale * 0.04)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: scale * 0.035, yRadius: scale * 0.035)
    NSColor(red: 0.07, green: 0.12, blue: 0.16, alpha: 1).setFill()
    screenPath.fill()
    // "Mirror" waves coming out of the phone.
    NSColor.white.withAlphaComponent(0.85).setStroke()
    for (index, radius) in [0.12, 0.2].enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: scale * 0.67, y: scale * 0.5), radius: scale * CGFloat(radius), startAngle: -42, endAngle: 42)
        arc.lineWidth = scale * 0.022
        arc.lineCapStyle = .round
        arc.stroke()
        _ = index
    }
    // Play triangle on the screen.
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: scale * 0.455, y: scale * 0.44))
    triangle.line(to: NSPoint(x: scale * 0.455, y: scale * 0.56))
    triangle.line(to: NSPoint(x: scale * 0.55, y: scale * 0.5))
    triangle.close()
    NSColor(red: 0.24, green: 0.78, blue: 0.45, alpha: 1).setFill()
    triangle.fill()

    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes { try render(size: size).write(to: output.appendingPathComponent("\(name).png")) }
