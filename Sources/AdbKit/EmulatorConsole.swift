import Foundation

/// The Android Emulator's telnet-style console (`geo fix`, `network speed`, `avd name`, `kill`, ...).
///
/// This is what `adb emu` does on the client side: connect to the emulator's console port (the
/// number in `emulator-5554`), authenticate with `~/.emulator_console_auth_token`, run the command.
/// (Do NOT use the adb server's `host:emulator:<port>` — that *registers* a new transport.)
public enum EmulatorConsole {
    public static func authToken() -> String? {
        let path = NSHomeDirectory() + "/.emulator_console_auth_token"
        return (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs one command and returns its output without the trailing `OK`. Throws on `KO`.
    @discardableResult
    public static func send(port: Int, command: String, token: String? = authToken()) throws -> String {
        let socket = try AdbSocket(host: "127.0.0.1", port: UInt16(port))
        socket.setReadTimeout(5)

        _ = try readReply(socket)  // banner, ends with OK
        if let token, !token.isEmpty {
            try socket.writeAll(Array("auth \(token)\n".utf8))
            _ = try readReply(socket)
        }
        try socket.writeAll(Array((command + "\n").utf8))
        let reply = try readReply(socket)
        try? socket.writeAll(Array("quit\n".utf8))
        return reply
    }

    /// Reads until a line that is exactly `OK` (success) or starts with `KO` (failure).
    private static func readReply(_ socket: AdbSocket) throws -> String {
        var text = ""
        while true {
            let chunk = try socket.readSome()
            if chunk.isEmpty { throw AdbError.unexpectedEOF }
            text += String(decoding: chunk, as: UTF8.self)
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            if let koLine = lines.first(where: { $0 == "KO" || $0.hasPrefix("KO:") }) {
                throw AdbError.adbFailure("Emulator console: \(koLine)")
            }
            if lines.last == "OK" {
                return lines.dropLast().joined(separator: "\n")
            }
        }
    }
}
