import Foundation

// Wire format reference: scrcpy v3.3.4, app/src/control_msg.c (`sc_control_msg_serialize`).
// All integers are big-endian. The protocol is internal to scrcpy and changes between releases,
// which is why `ScrcpyServer.version` is pinned and the matching jar ships in this package's resources.

public enum KeyAction: UInt8, Sendable { case down = 0, up = 1 }

public enum MotionAction: UInt8, Sendable {
    case down = 0, up = 1, move = 2, cancel = 3
    case hoverMove = 7, hoverEnter = 9, hoverExit = 10
}

public struct MotionButtons: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let primary = MotionButtons(rawValue: 1 << 0)
    public static let secondary = MotionButtons(rawValue: 1 << 1)
    public static let tertiary = MotionButtons(rawValue: 1 << 2)
    public static let back = MotionButtons(rawValue: 1 << 3)
    public static let forward = MotionButtons(rawValue: 1 << 4)
}

/// `KeyEvent.META_*` flags.
public struct MetaState: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let shift = MetaState(rawValue: 0x1)
    public static let alt = MetaState(rawValue: 0x2)
    public static let function = MetaState(rawValue: 0x8)
    public static let ctrl = MetaState(rawValue: 0x1000)
    public static let meta = MetaState(rawValue: 0x10000)
    public static let capsLock = MetaState(rawValue: 0x100000)
}

public enum CopyKey: UInt8, Sendable { case none = 0, copy = 1, cut = 2 }

/// Pointer ids understood by the server (`SC_POINTER_ID_*`).
public enum PointerID {
    public static let mouse = UInt64.max  // -1
    public static let genericFinger = UInt64.max - 1  // -2
    public static let virtualFinger = UInt64.max - 2  // -3
}

/// A point in the *current video frame's* coordinate space. The server silently drops events whose
/// `screenSize` differs from its own idea of the frame size, so it must be the decoded size.
public struct ScreenPosition: Sendable, Equatable {
    public var x: Int32
    public var y: Int32
    public var width: UInt16
    public var height: UInt16
    public init(x: Int32, y: Int32, width: UInt16, height: UInt16) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ControlMessage: Sendable, Equatable {
    case injectKeycode(action: KeyAction, keycode: Int32, repeatCount: UInt32 = 0, meta: MetaState = [])
    case injectText(String)
    case injectTouch(
        action: MotionAction, pointerID: UInt64, position: ScreenPosition, pressure: Float,
        actionButton: MotionButtons = [], buttons: MotionButtons = [])
    case injectScroll(position: ScreenPosition, horizontal: Float, vertical: Float, buttons: MotionButtons = [])
    case backOrScreenOn(KeyAction)
    case expandNotificationPanel
    case expandSettingsPanel
    case collapsePanels
    case getClipboard(CopyKey)
    case setClipboard(sequence: UInt64, text: String, paste: Bool)
    case setDisplayPower(Bool)
    case rotateDevice
    case startApp(String)
    case resetVideo

    static let maxTextBytes = 300
    static let maxClipboardBytes = (1 << 18) - 14

    public func serialize() -> [UInt8] {
        var out = ByteWriter()
        switch self {
        case .injectKeycode(let action, let keycode, let repeatCount, let meta):
            out.u8(0); out.u8(action.rawValue); out.i32(keycode); out.u32(repeatCount); out.u32(meta.rawValue)
        case .injectText(let text):
            out.u8(1); out.string32(text, maxBytes: Self.maxTextBytes)
        case .injectTouch(let action, let pointerID, let position, let pressure, let actionButton, let buttons):
            out.u8(2); out.u8(action.rawValue); out.u64(pointerID); out.position(position)
            out.u16(Self.fixedPointU16(pressure)); out.u32(actionButton.rawValue); out.u32(buttons.rawValue)
        case .injectScroll(let position, let horizontal, let vertical, let buttons):
            out.u8(3); out.position(position)
            // The wire carries [-16, 16] normalised to a signed 16-bit fixed point.
            out.u16(UInt16(bitPattern: Self.fixedPointI16(horizontal / 16)))
            out.u16(UInt16(bitPattern: Self.fixedPointI16(vertical / 16)))
            out.u32(buttons.rawValue)
        case .backOrScreenOn(let action):
            out.u8(4); out.u8(action.rawValue)
        case .expandNotificationPanel: out.u8(5)
        case .expandSettingsPanel: out.u8(6)
        case .collapsePanels: out.u8(7)
        case .getClipboard(let copyKey):
            out.u8(8); out.u8(copyKey.rawValue)
        case .setClipboard(let sequence, let text, let paste):
            out.u8(9); out.u64(sequence); out.u8(paste ? 1 : 0); out.string32(text, maxBytes: Self.maxClipboardBytes)
        case .setDisplayPower(let on):
            out.u8(10); out.u8(on ? 1 : 0)
        case .rotateDevice: out.u8(11)
        case .startApp(let name):
            out.u8(16); out.string8(name, maxBytes: 255)
        case .resetVideo: out.u8(17)
        }
        return out.bytes
    }

    static func fixedPointU16(_ value: Float) -> UInt16 {
        let clamped = min(max(value, 0), 1)
        return UInt16(min(UInt32(clamped * 65536), 0xFFFF))
    }

    static func fixedPointI16(_ value: Float) -> Int16 {
        let clamped = min(max(value, -1), 1)
        return Int16(min(Int32(clamped * 32768), 0x7FFF))
    }
}

struct ByteWriter {
    var bytes: [UInt8] = []

    mutating func u8(_ value: UInt8) { bytes.append(value) }
    mutating func u16(_ value: UInt16) { bytes += [UInt8(value >> 8), UInt8(value & 0xFF)] }
    mutating func u32(_ value: UInt32) { for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) } }
    mutating func i32(_ value: Int32) { u32(UInt32(bitPattern: value)) }
    mutating func u64(_ value: UInt64) { for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) } }

    mutating func position(_ position: ScreenPosition) {
        i32(position.x); i32(position.y); u16(position.width); u16(position.height)
    }

    /// UTF-8 truncated on a character boundary, with a 4-byte length prefix.
    mutating func string32(_ text: String, maxBytes: Int) {
        let data = Self.truncatedUTF8(text, maxBytes: maxBytes)
        u32(UInt32(data.count))
        bytes += data
    }

    /// Same, with a 1-byte length prefix.
    mutating func string8(_ text: String, maxBytes: Int) {
        let data = Self.truncatedUTF8(text, maxBytes: min(maxBytes, 255))
        u8(UInt8(data.count))
        bytes += data
    }

    static func truncatedUTF8(_ text: String, maxBytes: Int) -> [UInt8] {
        var result: [UInt8] = []
        for scalar in text.unicodeScalars {
            let encoded = Array(String(scalar).utf8)
            if result.count + encoded.count > maxBytes { break }
            result += encoded
        }
        return result
    }
}

// MARK: - Device → client messages

public enum DeviceMessage: Sendable, Equatable {
    case clipboard(String)
    case clipboardAck(sequence: UInt64)
    case uhidOutput(id: UInt16, data: [UInt8])
}

/// Incremental parser for the control socket's device→client direction.
public struct DeviceMessageParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public enum ParseError: Error { case unknownType(UInt8), messageTooLarge(Int) }

    /// scrcpy limits clipboard text to 256 KiB; anything far beyond that is not a real message.
    public static let maxClipboardLength = 1 << 20

    public mutating func feed(_ bytes: [UInt8]) throws -> [DeviceMessage] {
        buffer += bytes
        var messages: [DeviceMessage] = []
        while let (message, consumed) = try Self.parseOne(buffer) {
            messages.append(message)
            buffer.removeFirst(consumed)
        }
        return messages
    }

    private static func be32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
    }

    private static func parseOne(_ bytes: [UInt8]) throws -> (DeviceMessage, Int)? {
        guard let type = bytes.first else { return nil }
        switch type {
        case 0:
            guard bytes.count >= 5 else { return nil }
            let length = be32(bytes, 1)
            guard length <= maxClipboardLength else { throw ParseError.messageTooLarge(length) }
            guard bytes.count >= 5 + length else { return nil }
            return (.clipboard(String(decoding: bytes[5..<5 + length], as: UTF8.self)), 5 + length)
        case 1:
            guard bytes.count >= 9 else { return nil }
            var sequence: UInt64 = 0
            for byte in bytes[1..<9] { sequence = sequence << 8 | UInt64(byte) }
            return (.clipboardAck(sequence: sequence), 9)
        case 2:
            guard bytes.count >= 5 else { return nil }
            let id = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
            let size = Int(bytes[3]) << 8 | Int(bytes[4])
            guard bytes.count >= 5 + size else { return nil }
            return (.uhidOutput(id: id, data: Array(bytes[5..<5 + size])), 5 + size)
        default:
            throw ParseError.unknownType(type)
        }
    }
}
