import Foundation

/// Output produced by a long-running shell command.
public enum ShellEvent: Sendable, Equatable {
    case stdout(Data)
    case stderr(Data)
    case exit(Int)
}

/// A running device command (logcat, the scrcpy server, bugreportz, ...). Cancelling closes the
/// connection, which makes adbd tear the remote process down.
public final class ShellProcess: @unchecked Sendable {
    public let events: AsyncThrowingStream<ShellEvent, Error>
    private let box: SocketBox

    fileprivate init(box: SocketBox, events: AsyncThrowingStream<ShellEvent, Error>) {
        self.box = box
        self.events = events
    }

    public func cancel() { box.cancel() }
}

/// Holds a socket that is opened on a background thread, so the *consumer* can cancel before, during
/// or after the connection exists. (Connecting can block for a while when the adb server must be
/// started, which is why it never happens on the caller's thread.)
final class SocketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var socket: AdbSocket?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Stores the socket; returns `false` (after closing it) if cancellation already happened.
    func set(_ socket: AdbSocket) -> Bool {
        lock.withLock {
            if cancelled {
                socket.cancel()
                return false
            }
            self.socket = socket
            return true
        }
    }

    func cancel() {
        let existing: AdbSocket? = lock.withLock {
            cancelled = true
            return socket
        }
        existing?.cancel()
    }
}

extension AdbClient {
    /// Starts `command` with the v2 shell protocol and streams its output as it arrives.
    ///
    /// Never blocks the caller: connecting happens on the stream's own thread, and a connection error
    /// is delivered through the stream.
    public func shellStream(serial: String, _ command: String) -> ShellProcess {
        let box = SocketBox()
        let stream = AsyncThrowingStream<ShellEvent, Error> { continuation in
            continuation.onTermination = { _ in box.cancel() }
            let thread = Thread {
                do {
                    let socket = try self.openSocket()
                    guard box.set(socket) else {
                        continuation.finish()
                        return
                    }
                    try self.request(socket, "host:transport:\(serial)", serial: serial)
                    try self.request(socket, "shell,v2,raw:\(command)", serial: serial)
                    while true {
                        let header = try socket.readExactly(5)
                        let length = Int(header[1]) | Int(header[2]) << 8 | Int(header[3]) << 16 | Int(header[4]) << 24
                        let payload = try socket.readExactly(length)
                        switch header[0] {
                        case 1: continuation.yield(.stdout(Data(payload)))
                        case 2: continuation.yield(.stderr(Data(payload)))
                        case 3: continuation.yield(.exit(Int(payload.first ?? 0)))
                        default: break
                        }
                    }
                } catch AdbError.unexpectedEOF {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: box.isCancelled ? nil : error)
                }
            }
            thread.name = "adb.shell-stream"
            thread.start()
        }
        return ShellProcess(box: box, events: stream)
    }

    /// Streams a command's stdout straight into a file (no in-memory copy). Fails on a non-zero exit code.
    public func shellToFile(serial: String, _ command: String, to url: URL) async throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var stderr = Data()
        var exitCode = 0
        for try await event in shellStream(serial: serial, command).events {
            switch event {
            case .stdout(let data): try handle.write(contentsOf: data)
            case .stderr(let data): if stderr.count < 8192 { stderr.append(data) }
            case .exit(let code): exitCode = code
            }
        }
        guard exitCode == 0 else {
            throw AdbError.adbFailure("`\(command)` thoát với mã \(exitCode): \(String(decoding: stderr, as: UTF8.self))")
        }
    }

    /// Runs a command and returns its raw stdout (binary safe), failing on a non-zero exit code.
    public func shellData(serial: String, _ command: String) throws -> Data {
        let socket = try openSocket()
        try request(socket, "host:transport:\(serial)", serial: serial)
        try request(socket, "shell,v2,raw:\(command)", serial: serial)

        var stdout = Data()
        var stderr = Data()
        var exitCode = 0
        while true {
            let header: [UInt8]
            do { header = try socket.readExactly(5) } catch AdbError.unexpectedEOF { break }
            let length = Int(header[1]) | Int(header[2]) << 8 | Int(header[3]) << 16 | Int(header[4]) << 24
            let payload = try socket.readExactly(length)
            switch header[0] {
            case 1: stdout.append(contentsOf: payload)
            case 2: stderr.append(contentsOf: payload)
            case 3: exitCode = Int(payload.first ?? 0)
            default: break
            }
        }
        guard exitCode == 0 else {
            throw AdbError.adbFailure("`\(command)` thoát với mã \(exitCode): \(String(decoding: stderr, as: UTF8.self))")
        }
        return stdout
    }

    /// Runs a shell command and throws if it exits non-zero; returns trimmed stdout.
    @discardableResult
    public func run(serial: String, _ command: String) throws -> String {
        let result = try shell(serial: serial, command)
        guard result.exitCode == 0 else {
            let detail = [result.stderr, result.stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            throw AdbError.adbFailure("`\(command)` thoát với mã \(result.exitCode): \(detail)")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
