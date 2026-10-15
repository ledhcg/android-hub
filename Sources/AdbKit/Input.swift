import Foundation

/// Hardware/navigation buttons, plus the Android-specific extras.
public enum DeviceButton: String, Sendable, CaseIterable, Codable {
    case home, back, recents, power, volumeUp = "volume-up", volumeDown = "volume-down", mute
    case menu, search, assist, enter, delete, tab, escape
    case dpadUp = "dpad-up", dpadDown = "dpad-down", dpadLeft = "dpad-left", dpadRight = "dpad-right", dpadCenter = "dpad-center"
    case sleep, wakeup
    case notifications, quickSettings = "quick-settings", collapsePanels = "collapse-panels"

    /// `KeyEvent.KEYCODE_*`, or `nil` for the status-bar actions that are not key presses.
    public var keycode: Int? {
        switch self {
        case .home: 3
        case .back: 4
        case .recents: 187
        case .power: 26
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        case .menu: 82
        case .search: 84
        case .assist: 219
        case .enter: 66
        case .delete: 67
        case .tab: 61
        case .escape: 111
        case .dpadUp: 19
        case .dpadDown: 20
        case .dpadLeft: 21
        case .dpadRight: 22
        case .dpadCenter: 23
        case .sleep: 223
        case .wakeup: 224
        case .notifications, .quickSettings, .collapsePanels: nil
        }
    }

    var command: String {
        switch self {
        case .notifications: "cmd statusbar expand-notifications"
        case .quickSettings: "cmd statusbar expand-settings"
        case .collapsePanels: "cmd statusbar collapse"
        default: "input keyevent \(keycode!)"
        }
    }
}

extension AdbClient {
    public func press(_ button: DeviceButton, serial: String) throws {
        try run(serial: serial, button.command)
    }

    public func tap(serial: String, x: Int, y: Int) throws {
        try run(serial: serial, "input tap \(x) \(y)")
    }

    public func swipe(serial: String, from: (x: Int, y: Int), to: (x: Int, y: Int), durationMilliseconds: Int = 300) throws {
        try run(serial: serial, "input swipe \(from.x) \(from.y) \(to.x) \(to.y) \(durationMilliseconds)")
    }

    /// Types ASCII text through `input text`. Spaces become `%s` (the only escape `input` understands);
    /// newlines press Enter. Anything outside ASCII cannot be typed this way and is rejected rather than
    /// crashing `input` — the app types Unicode through the clipboard instead.
    public func type(serial: String, text: String) throws {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            throw AdbError.adbFailure("`input text` can only type ASCII. Use the app (paste via the clipboard) to enter Unicode characters such as Vietnamese.")
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if !line.isEmpty {
                // A literal "%" is typed as-is; only the two-character sequence "%s" is special to `input`.
                let encoded = line.replacingOccurrences(of: " ", with: "%s")
                try run(serial: serial, "input text \(SettingChange.shellQuote(encoded))")
            }
            if index < lines.count - 1 { try run(serial: serial, "input keyevent 66") }
        }
    }

    public func rotate(serial: String, to rotation: DeviceRotation) throws {
        try apply(.rotation(rotation), serial: serial)
    }
}
