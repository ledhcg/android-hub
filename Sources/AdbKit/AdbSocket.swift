import Foundation
import Darwin

/// Blocking TCP socket to the adb server (default 127.0.0.1:5037).
///
/// Reads block the calling thread, so streaming callers run it on a dedicated thread and use
/// `cancel()` from elsewhere to wake the reader up.
public final class AdbSocket: @unchecked Sendable {
    private let fd: Int32

    init(host: String, port: UInt16) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AdbError.io("socket(): \(Self.errnoMessage())") }

        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        // Input events are tiny and latency-sensitive; do not let Nagle batch them.
        setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &enabled, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            Darwin.close(descriptor)
            throw AdbError.io("invalid address: \(host)")
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let message = Self.errnoMessage()
            Darwin.close(descriptor)
            throw AdbError.serverUnreachable("\(host):\(port) (\(message))")
        }
        fd = descriptor
    }

    deinit { Darwin.close(fd) }

    /// Wakes any thread blocked in `readExactly`; it will then throw `.unexpectedEOF`.
    public func cancel() { shutdown(fd, SHUT_RDWR) }

    public func writeAll(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw in
                send(fd, raw.baseAddress! + offset, bytes.count - offset, 0)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                throw AdbError.io("send(): \(Self.errnoMessage())")
            }
        }
    }

    public func readExactly(_ count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress! + offset, count - offset, 0)
            }
            if received > 0 {
                offset += received
            } else if received == 0 {
                throw AdbError.unexpectedEOF
            } else if errno == EINTR {
                continue
            } else {
                throw AdbError.io("recv(): \(Self.errnoMessage())")
            }
        }
        return buffer
    }

    /// Reads whatever is available (at least one byte, at most `limit`). Empty array means EOF.
    public func readSome(limit: Int = 64 * 1024) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: limit)
        while true {
            let received = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress!, limit, 0) }
            if received > 0 { return Array(buffer[..<received]) }
            if received == 0 { return [] }
            if errno == EINTR { continue }
            throw AdbError.io("recv(): \(Self.errnoMessage())")
        }
    }

    public func readToEnd() throws -> [UInt8] {
        var all: [UInt8] = []
        while true {
            let chunk = try readSome()
            if chunk.isEmpty { return all }
            all += chunk
        }
    }

    /// Fails reads that stay idle longer than `seconds` (0 disables the timeout).
    public func setReadTimeout(_ seconds: Double) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    /// adb's 4-digit lowercase-hex length prefix, e.g. `001f`.
    public func readHexLength() throws -> Int {
        let digits = String(decoding: try readExactly(4), as: UTF8.self)
        guard let length = Int(digits, radix: 16) else {
            throw AdbError.protocolViolation("length is not hex: '\(digits)'")
        }
        return length
    }

    private static func errnoMessage() -> String { String(cString: strerror(errno)) }
}
