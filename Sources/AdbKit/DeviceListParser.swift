import Foundation

/// Parses the text returned by `host:devices-l` / `host:track-devices-l`.
///
///     c2f55a15               unauthorized usb:0-1 transport_id:1
///     emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:2
public enum DeviceListParser {
    public static func parse(_ text: String) -> [Device] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> Device? {
        var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 2 else { return nil }

        let serial = tokens.removeFirst()
        var stateText = tokens.removeFirst()
        // "no permissions" is the one state that spans two tokens (followed by a bracketed hint).
        if stateText == "no", tokens.first?.hasPrefix("permissions") == true {
            stateText = "no permissions"
            tokens.removeFirst()
        }

        var properties: [String: String] = [:]
        for token in tokens {
            guard let colon = token.firstIndex(of: ":"), !token.hasPrefix("[") else { continue }
            properties[String(token[..<colon])] = String(token[token.index(after: colon)...])
        }

        let usbPath = properties["usb"]
        let connection: ConnectionKind =
            serial.hasPrefix("emulator-") ? .emulator
            : usbPath != nil ? .usb
            : .network

        return Device(
            serial: serial,
            state: DeviceState(adbString: stateText),
            connection: connection,
            usbPath: usbPath,
            product: properties["product"],
            model: properties["model"],
            codename: properties["device"],
            transportId: properties["transport_id"].flatMap(Int.init)
        )
    }
}
