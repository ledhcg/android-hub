import Foundation

/// An entry returned by the sync `LIST`/`STAT` services.
public struct RemoteFileEntry: Sendable, Equatable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let mode: UInt32
    public let size: UInt64
    public let modified: Date

    public var isDirectory: Bool { mode & 0o170000 == 0o040000 }
    public var isSymlink: Bool { mode & 0o170000 == 0o120000 }
    public var isRegularFile: Bool { mode & 0o170000 == 0o100000 }
    /// `drwxr-xr-x` style string.
    public var permissionString: String {
        let kind: Character = isDirectory ? "d" : isSymlink ? "l" : "-"
        let bits: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"), (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String([kind] + bits.map { mode & $0.0 != 0 ? $0.1 : "-" })
    }
}

/// The adb file-sync protocol (`sync:` service): list, stat, pull and push files without any shell.
///
/// One session = one socket; operations are sequential. Create a new session per concurrent transfer.
public final class AdbSyncSession: @unchecked Sendable {
    private let socket: AdbSocket
    /// `STA2`/`LIS2` carry 64-bit sizes and times; v1 truncates both to 32 bits (files ≥ 4 GiB).
    private let usesV2: Bool
    private static let maxChunk = 64 * 1024

    init(socket: AdbSocket, usesV2: Bool = false) {
        self.socket = socket
        self.usesV2 = usesV2
    }

    deinit { try? sendRequest("QUIT", length: 0) }

    // MARK: Requests

    private func sendRequest(_ id: String, length: Int, payload: [UInt8] = []) throws {
        var bytes = Array(id.utf8)
        bytes += Self.le32(UInt32(length))
        bytes += payload
        try socket.writeAll(bytes)
    }

    private func sendPathRequest(_ id: String, _ argument: String) throws {
        let payload = Array(argument.utf8)
        try sendRequest(id, length: payload.count, payload: payload)
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24 & 0xff)]
    }

    private static func readLE32(_ bytes: [UInt8], at offset: Int = 0) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private func readStatus() throws -> (id: String, value: UInt32) {
        let header = try socket.readExactly(8)
        return (String(decoding: header[0..<4], as: UTF8.self), Self.readLE32(header, at: 4))
    }

    private func failure(length: UInt32) throws -> AdbError {
        .adbFailure(String(decoding: try socket.readExactly(Int(length)), as: UTF8.self))
    }

    // MARK: Operations

    /// `nil` when the path does not exist.
    public func stat(_ path: String) throws -> RemoteFileEntry? {
        if usesV2 { return try statV2(path) }
        try sendPathRequest("STAT", path)
        let response = try socket.readExactly(16)
        guard String(decoding: response[0..<4], as: UTF8.self) == "STAT" else {
            throw AdbError.protocolViolation("STAT trả về '\(String(decoding: response[0..<4], as: UTF8.self))'")
        }
        let mode = Self.readLE32(response, at: 4)
        if mode == 0 { return nil }
        return RemoteFileEntry(
            name: (path as NSString).lastPathComponent, mode: mode, size: UInt64(Self.readLE32(response, at: 8)),
            modified: Date(timeIntervalSince1970: TimeInterval(Self.readLE32(response, at: 12))))
    }

    /// `struct sync_stat_v2`: id, error, dev(8), ino(8), mode, nlink, uid, gid, size(8), atime(8), mtime(8), ctime(8) = 72 bytes.
    private func statV2(_ path: String) throws -> RemoteFileEntry? {
        try sendPathRequest("STA2", path)
        let response = try socket.readExactly(72)
        guard String(decoding: response[0..<4], as: UTF8.self) == "STA2" else {
            throw AdbError.protocolViolation("STA2 trả về '\(String(decoding: response[0..<4], as: UTF8.self))'")
        }
        if Self.readLE32(response, at: 4) != 0 { return nil }  // errno (ENOENT, EACCES, ...)
        return RemoteFileEntry(
            name: (path as NSString).lastPathComponent, mode: Self.readLE32(response, at: 24),
            size: Self.readLE64(response, at: 40), modified: Self.date(Self.readLE64(response, at: 56)))
    }

    /// Entry names come from the device; a hostile or buggy adbd must not be able to smuggle a path.
    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    public func list(_ path: String) throws -> [RemoteFileEntry] {
        if usesV2 { return try listV2(path) }
        try sendPathRequest("LIST", path)
        var entries: [RemoteFileEntry] = []
        while true {
            let header = try socket.readExactly(4)
            let id = String(decoding: header, as: UTF8.self)
            if id == "DONE" {
                _ = try socket.readExactly(16)
                return entries
            }
            guard id == "DENT" else { throw AdbError.protocolViolation("LIST trả về '\(id)'") }
            let fields = try socket.readExactly(16)
            let nameLength = Int(Self.readLE32(fields, at: 12))
            let name = String(decoding: try socket.readExactly(nameLength), as: UTF8.self)
            guard Self.isSafeName(name) else { continue }
            entries.append(
                RemoteFileEntry(
                    name: name, mode: Self.readLE32(fields, at: 0), size: UInt64(Self.readLE32(fields, at: 4)),
                    modified: Date(timeIntervalSince1970: TimeInterval(Self.readLE32(fields, at: 8)))))
        }
    }

    /// `struct sync_dent_v2` = the 72-byte stat layout (with `DNT2` as id) followed by namelen(4) and the name.
    private func listV2(_ path: String) throws -> [RemoteFileEntry] {
        try sendPathRequest("LIS2", path)
        var entries: [RemoteFileEntry] = []
        while true {
            let header = try socket.readExactly(4)
            let id = String(decoding: header, as: UTF8.self)
            if id == "DONE" {
                _ = try socket.readExactly(72)  // the terminator is a zero-filled dent_v2 (76 bytes in total)
                return entries
            }
            guard id == "DNT2" else { throw AdbError.protocolViolation("LIS2 trả về '\(id)'") }
            let fields = try socket.readExactly(72)  // error … ctime, namelen
            let nameLength = Int(Self.readLE32(fields, at: 68))
            let name = String(decoding: try socket.readExactly(nameLength), as: UTF8.self)
            guard Self.isSafeName(name) else { continue }
            entries.append(
                RemoteFileEntry(
                    name: name, mode: Self.readLE32(fields, at: 20), size: Self.readLE64(fields, at: 36),
                    modified: Self.date(Self.readLE64(fields, at: 52))))
        }
    }

    private static func readLE64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in (0..<8).reversed() { value = value << 8 | UInt64(bytes[offset + index]) }
        return value
    }

    private static func date(_ seconds: UInt64) -> Date { Date(timeIntervalSince1970: TimeInterval(Int64(bitPattern: seconds))) }

    /// The wire carries a 32-bit mtime; clamp instead of trapping on dates outside 1970…2106.
    private static func wireTime(_ date: Date) -> Int {
        Int(UInt32(clamping: Int64(min(max(date.timeIntervalSince1970, 0), Double(UInt32.max)))))
    }

    /// Downloads `remote` to `local`. The data lands in `local.part` and replaces `local` only after the
    /// whole transfer succeeded, so a failed or interrupted pull never destroys an existing file.
    /// `progress` receives the number of bytes written so far.
    public func pull(_ remote: String, to local: URL, progress: (@Sendable (UInt64) -> Void)? = nil) throws {
        try sendPathRequest("RECV", remote)
        let partial = local.appendingPathExtension("part")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        var finished = false
        defer {
            try? handle.close()
            if !finished { try? FileManager.default.removeItem(at: partial) }
        }

        var total: UInt64 = 0
        loop: while true {
            let (id, value) = try readStatus()
            switch id {
            case "DATA":
                let chunk = try socket.readExactly(Int(value))
                try handle.write(contentsOf: chunk)
                total += UInt64(chunk.count)
                progress?(total)
            case "DONE":
                break loop
            case "FAIL":
                throw try failure(length: value)
            default:
                throw AdbError.protocolViolation("RECV trả về '\(id)'")
            }
        }
        try handle.close()
        if FileManager.default.fileExists(atPath: local.path) {
            _ = try FileManager.default.replaceItemAt(local, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: local)
        }
        finished = true
    }

    /// Reads a remote file into memory.
    public func pullData(_ remote: String) throws -> Data {
        try sendPathRequest("RECV", remote)
        var data = Data()
        while true {
            let (id, value) = try readStatus()
            switch id {
            case "DATA": data.append(contentsOf: try socket.readExactly(Int(value)))
            case "DONE": return data
            case "FAIL": throw try failure(length: value)
            default: throw AdbError.protocolViolation("RECV trả về '\(id)'")
            }
        }
    }

    /// Uploads `local` to `remote`. `progress` receives (bytesSent, totalBytes).
    public func push(
        _ local: URL, to remote: String, mode: UInt32 = 0o100644,
        progress: (@Sendable (UInt64, UInt64) -> Void)? = nil
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: local.path)
        let total = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date) ?? Date()

        let target = "\(remote),\(mode)"
        try sendPathRequest("SEND", target)

        let handle = try FileHandle(forReadingFrom: local)
        defer { try? handle.close() }
        var sent: UInt64 = 0
        while let chunk = try handle.read(upToCount: Self.maxChunk), !chunk.isEmpty {
            try sendRequest("DATA", length: chunk.count, payload: [UInt8](chunk))
            sent += UInt64(chunk.count)
            progress?(sent, total)
        }
        try sendRequest("DONE", length: Self.wireTime(modified))
        try finishPush()
    }

    /// Uploads in-memory data.
    public func push(_ data: Data, to remote: String, mode: UInt32 = 0o100644, modified: Date = Date()) throws {
        try sendPathRequest("SEND", "\(remote),\(mode)")
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.maxChunk, data.count)
            try sendRequest("DATA", length: end - offset, payload: [UInt8](data[offset..<end]))
            offset = end
        }
        try sendRequest("DONE", length: Self.wireTime(modified))
        try finishPush()
    }

    private func finishPush() throws {
        let (id, value) = try readStatus()
        switch id {
        case "OKAY": return
        case "FAIL": throw try failure(length: value)
        default: throw AdbError.protocolViolation("SEND trả về '\(id)'")
        }
    }
}

extension AdbClient {
    /// Features advertised by a device's adbd (`stat_v2`, `ls_v2`, `shell_v2`, ...).
    public func deviceFeatures(serial: String) throws -> Set<String> {
        let reply = try hostQuery("host-serial:\(serial):features")
        return Set(reply.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// Opens a sync session on a device, using the 64-bit v2 `STAT`/`LIST` when adbd supports them.
    public func syncSession(serial: String) throws -> AdbSyncSession {
        let features = (try? deviceFeatures(serial: serial)) ?? []
        let socket = try openSocket()
        try request(socket, "host:transport:\(serial)", serial: serial)
        try request(socket, "sync:", serial: serial)
        return AdbSyncSession(socket: socket, usesV2: features.contains("stat_v2") && features.contains("ls_v2"))
    }
}
