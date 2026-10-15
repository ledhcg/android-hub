import Foundation

/// Finds the `adb` executable the same way a developer's shell would.
public enum AdbLocator {
    public static func find(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty { candidates.append("\(root)/platform-tools/adb") }
        }
        candidates.append("\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb")
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(directory)/adb")
        }
        candidates += ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

/// Client for the adb *server* protocol (https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/OVERVIEW.TXT).
///
/// Every call opens its own short-lived socket, exactly like the `adb` CLI does, so the struct is
/// trivially `Sendable` and safe to share between a UI and background tasks.
public struct AdbClient: Sendable {
    public let host: String
    public let port: UInt16
    public let adbExecutable: URL?

    public init(
        host: String = "127.0.0.1",
        port: UInt16 = UInt16(ProcessInfo.processInfo.environment["ANDROID_ADB_SERVER_PORT"] ?? "") ?? 5037,
        adbExecutable: URL? = AdbLocator.find()
    ) {
        self.host = host
        self.port = port
        self.adbExecutable = adbExecutable
    }

    // MARK: - Server

    public func serverVersion() throws -> Int {
        let socket = try openSocket()
        try request(socket, "host:version")
        let length = try socket.readHexLength()
        let text = String(decoding: try socket.readExactly(length), as: UTF8.self)
        guard let version = Int(text, radix: 16) else { throw AdbError.protocolViolation("version: '\(text)'") }
        return version
    }

    // MARK: - Devices

    /// Snapshot of attached devices. USB names from the I/O Registry are merged in when `enrichWithUSB` is set.
    public func devices(enrichWithUSB: Bool = true) throws -> [Device] {
        let socket = try openSocket()
        try request(socket, "host:devices-l")
        let length = try socket.readHexLength()
        let text = String(decoding: try socket.readExactly(length), as: UTF8.self)
        let devices = DeviceListParser.parse(text)
        return enrichWithUSB ? Self.enrich(devices) : devices
    }

    /// Emits the full device list every time it changes (and once immediately), until cancelled.
    ///
    /// Connecting (which may have to start the adb server) happens on the stream's own thread, so
    /// calling this from the main thread never blocks.
    public func trackDevices(enrichWithUSB: Bool = true) -> AsyncThrowingStream<[Device], Error> {
        AsyncThrowingStream { continuation in
            let box = SocketBox()
            continuation.onTermination = { _ in box.cancel() }
            let thread = Thread {
                do {
                    let socket = try self.openSocket()
                    guard box.set(socket) else {
                        continuation.finish()
                        return
                    }
                    try self.request(socket, "host:track-devices-l")
                    while true {
                        let length = try socket.readHexLength()
                        let text = length == 0 ? "" : String(decoding: try socket.readExactly(length), as: UTF8.self)
                        let devices = DeviceListParser.parse(text)
                        continuation.yield(enrichWithUSB ? Self.enrich(devices) : devices)
                    }
                } catch {
                    continuation.finish(throwing: box.isCancelled ? nil : error)
                }
            }
            thread.name = "adb.track-devices"
            thread.start()
        }
    }

    // MARK: - Shell

    public struct ShellResult: Sendable, Equatable {
        public let exitCode: Int
        public let stdout: String
        public let stderr: String
    }

    /// Runs `command` on the device with the v2 shell protocol (Android 7+), which keeps stdout,
    /// stderr and the exit code separate.
    public func shell(serial: String, _ command: String) throws -> ShellResult {
        let socket = try openSocket()
        try request(socket, "host:transport:\(serial)", serial: serial)
        try request(socket, "shell,v2,raw:\(command)", serial: serial)

        var stdout: [UInt8] = []
        var stderr: [UInt8] = []
        var exitCode = 0
        while true {
            let header: [UInt8]
            do { header = try socket.readExactly(5) } catch AdbError.unexpectedEOF { break }
            let length = Int(header[1]) | Int(header[2]) << 8 | Int(header[3]) << 16 | Int(header[4]) << 24
            let payload = try socket.readExactly(length)
            switch header[0] {
            case 1: stdout += payload
            case 2: stderr += payload
            case 3: exitCode = Int(payload.first ?? 0)
            default: break  // 0/4 are stdin-direction packets; never sent by the device
            }
        }
        return ShellResult(
            exitCode: exitCode,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self)
        )
    }

    // MARK: - Plumbing

    func openSocket() throws -> AdbSocket {
        do {
            return try AdbSocket(host: host, port: port)
        } catch AdbError.serverUnreachable {
            try startServer()
            return try AdbSocket(host: host, port: port)
        }
    }

    private func startServer() throws {
        guard let adbExecutable else { throw AdbError.adbNotFound }
        let process = Process()
        process.executableURL = adbExecutable
        process.arguments = ["-P", String(port), "start-server"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AdbError.serverUnreachable("`adb start-server` exited with code \(process.terminationStatus)")
        }
    }

    /// Sends one length-prefixed request and consumes the `OKAY`/`FAIL` status.
    func request(_ socket: AdbSocket, _ payload: String, serial: String? = nil) throws {
        let body = Array(payload.utf8)
        try socket.writeAll(Array(String(format: "%04x", body.count).utf8) + body)

        let status = String(decoding: try socket.readExactly(4), as: UTF8.self)
        switch status {
        case "OKAY":
            return
        case "FAIL":
            let length = try socket.readHexLength()
            let message = String(decoding: try socket.readExactly(length), as: UTF8.self)
            throw Self.failure(message, serial: serial)
        default:
            throw AdbError.protocolViolation("status '\(status)'")
        }
    }

    static func failure(_ message: String, serial: String?) -> AdbError {
        let lowered = message.lowercased()
        let id = serial ?? "?"
        if lowered.contains("unauthorized") { return .deviceUnauthorized(serial: id) }
        if lowered.contains("offline") { return .deviceOffline(serial: id) }
        if lowered.contains("not found") { return .deviceNotFound(id) }
        return .adbFailure(message)
    }

    private static func enrich(_ devices: [Device]) -> [Device] {
        let registry = MacUSBRegistry.entriesBySerial()
        return devices.map { device in
            guard let entry = registry[device.serial] else { return device }
            var copy = device
            copy.usbVendorName = entry.vendorName
            copy.usbProductName = entry.productName
            return copy
        }
    }
}
