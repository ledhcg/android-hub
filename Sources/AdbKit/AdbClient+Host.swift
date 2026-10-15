import Foundation

/// A device advertising itself over mDNS for wireless debugging (Android 11+).
public struct MdnsService: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// `_adb-tls-pairing._tcp` — shown while "Pair device with pairing code" is open on the phone.
        case pairing
        /// `_adb-tls-connect._tcp` — a device that is already paired and can be connected to.
        case connect
        case other
    }

    public let name: String
    public let kind: Kind
    public let address: String  // host:port
}

// MARK: - Host services (no device needed)

extension AdbClient {
    /// Sends a `host:` request and returns the length-prefixed text reply.
    func hostQuery(_ payload: String) throws -> String {
        let socket = try openSocket()
        try request(socket, payload)
        let length = try socket.readHexLength()
        return String(decoding: try socket.readExactly(length), as: UTF8.self)
    }

    /// Pairs with a phone showing "Pair device with pairing code" (Android 11+).
    public func pair(address: String, code: String) throws -> String {
        let reply = try hostQuery("host:pair:\(code):\(address)")
        if reply.lowercased().hasPrefix("failed") { throw AdbError.adbFailure(reply) }
        return reply
    }

    /// `adb connect host:port` (TCP/IP and wireless-debugging devices).
    public func connect(address: String) throws -> String {
        let target = address.contains(":") ? address : "\(address):5555"
        let reply = try hostQuery("host:connect:\(target)")
        let lowered = reply.lowercased()
        if lowered.hasPrefix("failed") || lowered.contains("unable to connect") || lowered.contains("cannot connect") {
            throw AdbError.adbFailure(reply)
        }
        return reply
    }

    /// Disconnects one network device, or every one when `address` is `nil`.
    public func disconnect(address: String? = nil) throws {
        _ = try hostQuery("host:disconnect:\(address ?? "")")
    }

    public func killServer() throws {
        let socket = try openSocket()
        // The server answers OKAY and exits; ignore a reset while it is shutting down.
        try? request(socket, "host:kill")
    }

    /// Devices and pairing endpoints advertised on the local network.
    public func discoverWirelessServices() throws -> [MdnsService] {
        Self.parseMdns(try hostQuery("host:mdns:services"))
    }

    static func parseMdns(_ text: String) -> [MdnsService] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            let kind: MdnsService.Kind =
                fields[1].contains("_adb-tls-pairing") ? .pairing
                : fields[1].contains("_adb-tls-connect") ? .connect
                : .other
            return MdnsService(name: fields[0], kind: kind, address: fields[2].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Restarts adbd on a USB-connected device in TCP/IP mode (required for pre-Android-11 phones such as the Mi 8).
    public func enableTCPIP(serial: String, port: Int = 5555) throws -> String {
        let socket = try openSocket()
        try request(socket, "host:transport:\(serial)", serial: serial)
        try request(socket, "tcpip:\(port)", serial: serial)
        return String(decoding: try socket.readToEnd(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The device's Wi-Fi IPv4 address, if it has one.
    public func wifiAddress(serial: String) throws -> String? {
        let result = try shell(serial: serial, "ip -f inet addr show wlan0; ip route")
        return Self.parseWifiAddress(result.stdout)
    }

    static func parseWifiAddress(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet "), let slash = trimmed.firstIndex(of: "/") {
                return String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<slash])
            }
        }
        for line in text.split(whereSeparator: \.isNewline) where line.contains("wlan0") {
            let parts = line.split(separator: " ")
            if let index = parts.firstIndex(of: "src"), index + 1 < parts.count { return String(parts[index + 1]) }
        }
        return nil
    }

    /// Opens a direct stream to an abstract-namespace unix socket on the device (no host port is allocated).
    public func openLocalAbstract(serial: String, name: String) throws -> AdbSocket {
        let socket = try openSocket()
        try request(socket, "host:transport:\(serial)", serial: serial)
        try request(socket, "localabstract:\(name)", serial: serial)
        return socket
    }

    /// Sends a command to the Android Emulator console (`geo fix`, `network speed`, `kill`, ...).
    @discardableResult
    public func emulatorCommand(serial: String, _ command: String) throws -> String {
        guard serial.hasPrefix("emulator-"), let port = Int(serial.dropFirst("emulator-".count)) else {
            throw AdbError.adbFailure("'\(serial)' is not an emulator.")
        }
        return try EmulatorConsole.send(port: port, command: command)
    }
}
