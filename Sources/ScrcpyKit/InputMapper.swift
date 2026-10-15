import CoreGraphics
import Foundation

/// Turns normalised pointer positions (0…1 inside the visible video) into scrcpy touch messages.
///
/// Pure value logic with no AppKit dependency so the gesture rules are unit-testable. The caller owns
/// the NSView and feeds this with already-converted coordinates.
///
/// - Left button → one finger. Holding Option when pressing adds a mirrored second finger (pinch),
///   exactly like scrcpy's Ctrl-drag.
/// - Right button → Back (or wake the screen); middle button → Home.
public struct PointerMapper: Sendable {
    public private(set) var frameSize: FrameSize
    public private(set) var isTouching = false
    private var isPinching = false

    public init(frameSize: FrameSize) { self.frameSize = frameSize }

    /// The frame size changes on rotation/resize; any touch in flight is cancelled by the caller.
    public mutating func updateFrameSize(_ size: FrameSize) { frameSize = size }

    public func position(for normalized: CGPoint) -> ScreenPosition {
        let width = max(frameSize.width, 1)
        let height = max(frameSize.height, 1)
        let x = Int32(min(max(normalized.x, 0), 1) * Double(width - 1))
        let y = Int32(min(max(normalized.y, 0), 1) * Double(height - 1))
        return ScreenPosition(x: x, y: y, width: UInt16(clamping: width), height: UInt16(clamping: height))
    }

    private func mirrored(_ position: ScreenPosition) -> ScreenPosition {
        ScreenPosition(x: Int32(position.width) - position.x, y: Int32(position.height) - position.y, width: position.width, height: position.height)
    }

    public mutating func mouseDown(at point: CGPoint, pinch: Bool) -> [ControlMessage] {
        let p = position(for: point)
        isTouching = true
        isPinching = pinch
        var messages: [ControlMessage] = [
            .injectTouch(action: .down, pointerID: PointerID.mouse, position: p, pressure: 1, actionButton: .primary, buttons: .primary)
        ]
        if pinch {
            messages.append(
                .injectTouch(action: .down, pointerID: PointerID.virtualFinger, position: mirrored(p), pressure: 1))
        }
        return messages
    }

    public mutating func mouseDragged(to point: CGPoint) -> [ControlMessage] {
        guard isTouching else { return [] }
        let p = position(for: point)
        var messages: [ControlMessage] = [
            .injectTouch(action: .move, pointerID: PointerID.mouse, position: p, pressure: 1, buttons: .primary)
        ]
        if isPinching {
            messages.append(.injectTouch(action: .move, pointerID: PointerID.virtualFinger, position: mirrored(p), pressure: 1))
        }
        return messages
    }

    public mutating func mouseUp(at point: CGPoint) -> [ControlMessage] {
        guard isTouching else { return [] }
        let p = position(for: point)
        var messages: [ControlMessage] = [
            .injectTouch(action: .up, pointerID: PointerID.mouse, position: p, pressure: 0, actionButton: .primary)
        ]
        if isPinching {
            messages.append(.injectTouch(action: .up, pointerID: PointerID.virtualFinger, position: mirrored(p), pressure: 0))
        }
        isTouching = false
        isPinching = false
        return messages
    }

    /// Lifts every finger (focus lost, window closed, rotation) so Android never sees a stuck touch.
    public mutating func cancelTouches(at point: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> [ControlMessage] {
        isTouching ? mouseUp(at: point) : []
    }

    public func back() -> [ControlMessage] { [.backOrScreenOn(.down), .backOrScreenOn(.up)] }

    public func home() -> [ControlMessage] {
        [.injectKeycode(action: .down, keycode: 3), .injectKeycode(action: .up, keycode: 3)]
    }

    /// `horizontal`/`vertical` are in scroll "lines" (positive = up/left content direction as AppKit reports).
    public func scroll(at point: CGPoint, horizontal: Float, vertical: Float) -> [ControlMessage] {
        [.injectScroll(position: position(for: point), horizontal: horizontal, vertical: vertical)]
    }
}

public enum KeyMapping: Equatable, Sendable {
    /// A non-text key (arrows, Enter, F-keys, shortcuts) sent as down+up key events.
    case key(keycode: Int32, meta: MetaState)
    /// Printable text, including IME-composed Vietnamese, sent with `injectText`.
    case text(String)
    case paste
    case copy
    case cut
    case ignored
}

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = KeyModifiers(rawValue: 1)
    public static let control = KeyModifiers(rawValue: 2)
    public static let option = KeyModifiers(rawValue: 4)
    public static let command = KeyModifiers(rawValue: 8)
}

public enum KeyMapper {
    /// macOS virtual key code → `KeyEvent.KEYCODE_*` for keys that are not text.
    static let special: [UInt16: Int32] = [
        0x24: 66, 0x4C: 66,  // Return, keypad Enter
        0x30: 61,  // Tab
        0x33: 67,  // Delete (backspace) → KEYCODE_DEL
        0x75: 112,  // Forward delete
        0x35: 111,  // Escape
        0x7B: 21, 0x7C: 22, 0x7D: 20, 0x7E: 19,  // arrows (left, right, down, up)
        0x73: 122, 0x77: 123,  // Home, End → MOVE_HOME, MOVE_END
        0x74: 92, 0x79: 93,  // Page up/down
        0x7A: 131, 0x78: 132, 0x63: 133, 0x76: 134, 0x60: 135, 0x61: 136,  // F1…F6
        0x62: 137, 0x64: 138, 0x65: 139, 0x6D: 140, 0x67: 141, 0x6F: 142,  // F7…F12
    ]

    /// `KEYCODE_A`…`KEYCODE_Z` = 29…54, digits `KEYCODE_0`…`9` = 7…16.
    static func androidKeycode(forCharacter character: Character) -> Int32? {
        guard let scalar = character.lowercased().unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x61...0x7A: return Int32(scalar.value - 0x61) + 29
        case 0x30...0x39: return Int32(scalar.value - 0x30) + 7
        default: return nil
        }
    }

    public static func map(
        keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?, modifiers: KeyModifiers
    ) -> KeyMapping {
        var meta: MetaState = []
        if modifiers.contains(.shift) { meta.insert(.shift) }
        if modifiers.contains(.option) { meta.insert(.alt) }
        if modifiers.contains(.control) { meta.insert(.ctrl) }

        if let code = special[keyCode] {
            return .key(keycode: code, meta: meta)
        }

        if modifiers.contains(.command) {
            guard let first = charactersIgnoringModifiers?.first else { return .ignored }
            switch first.lowercased() {
            case "v": return .paste
            case "c": return .copy
            case "x": return .cut
            default:
                // Cmd+<letter> → Ctrl+<letter> (select all, undo, ...), the Android equivalent shortcut.
                guard let code = androidKeycode(forCharacter: first) else { return .ignored }
                return .key(keycode: code, meta: meta.union(.ctrl))
            }
        }
        if modifiers.contains(.control) {
            guard let first = charactersIgnoringModifiers?.first, let code = androidKeycode(forCharacter: first) else { return .ignored }
            return .key(keycode: code, meta: meta)
        }

        guard let characters, !characters.isEmpty else { return .ignored }
        // Private-use scalars are how AppKit reports function/arrow keys; never type those.
        if characters.unicodeScalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }) { return .ignored }
        return .text(characters)
    }
}
