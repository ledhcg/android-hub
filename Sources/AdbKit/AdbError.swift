import Foundation

public enum AdbError: Error, Sendable, Equatable {
    case adbNotFound
    case serverUnreachable(String)
    case unexpectedEOF
    case io(String)
    case protocolViolation(String)
    /// The adb server answered `FAIL` with this message.
    case adbFailure(String)

    case deviceNotFound(String)
    case deviceUnauthorized(serial: String)
    case deviceOffline(serial: String)

    case noDeviceSpecified(candidates: [String])
    case ambiguousDevice(query: String, candidates: [String])
}

extension AdbError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .adbNotFound:
            return "`adb` not found. Set ANDROID_HOME or add platform-tools to PATH."
        case .serverUnreachable(let detail):
            return "Could not connect to the adb server: \(detail)"
        case .unexpectedEOF:
            return "The adb server closed the connection unexpectedly."
        case .io(let detail):
            return "I/O error: \(detail)"
        case .protocolViolation(let detail):
            return "Invalid adb response: \(detail)"
        case .adbFailure(let message):
            return "adb rejected the request: \(message)"
        case .deviceNotFound(let id):
            return "Device not found: '\(id)'."
        case .deviceUnauthorized(let serial):
            return """
                Device \(serial) has not authorized USB debugging for this computer.
                Unlock the phone and tap Allow in the "Allow USB debugging?" dialog \
                (or revoke USB debugging authorizations in Developer options and replug the cable).
                """
        case .deviceOffline(let serial):
            return "Device \(serial) is offline. Try replugging the cable or running `adb reconnect`."
        case .noDeviceSpecified(let candidates):
            return "Specify --device. Available devices: \(candidates.isEmpty ? "(none)" : candidates.joined(separator: ", "))"
        case .ambiguousDevice(let query, let candidates):
            return "'\(query)' matches multiple devices: \(candidates.joined(separator: ", "))"
        }
    }
}
