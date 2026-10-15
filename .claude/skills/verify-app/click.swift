import CoreGraphics
import Foundation

// Posts a real left click at screen coordinates (needs Accessibility permission for the terminal).
// usage: swift click.swift <x> <y>      (screen point = window origin + point inside the window)
let arguments = CommandLine.arguments
guard arguments.count == 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: click.swift <x> <y>\n".utf8))
    exit(1)
}
let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(80_000)
}
