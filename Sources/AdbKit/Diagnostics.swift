import Foundation

public enum LogLevel: Character, Sendable, Codable, CaseIterable, Comparable {
    case verbose = "V", debug = "D", info = "I", warning = "W", error = "E", fatal = "F", silent = "S"

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}

public struct LogEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: Int
    public let timestamp: String
    public let pid: Int
    public let tid: Int
    public let level: LogLevel
    public let tag: String
    public let message: String
}

public enum LogParser {
    /// `10-14 04:11:52.123  1234  5678 I ActivityManager: Start proc ...` (logcat -v threadtime)
    public static func parse(line: String, id: Int) -> LogEntry? {
        // Columns are fixed-width enough to tokenise: date, time, pid, tid, level, "tag:" then message.
        let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard parts.count >= 6, parts[0].count == 5, parts[0].contains("-"), parts[1].contains(":"),
            let pid = Int(parts[2]), let tid = Int(parts[3]), parts[4].count == 1,
            let level = LogLevel(rawValue: parts[4].first!)
        else { return nil }
        let rest = String(parts[5])
        guard let colon = rest.range(of: ": ") ?? (rest.hasSuffix(":") ? rest.range(of: ":", options: .backwards) : nil) else {
            return LogEntry(id: id, timestamp: "\(parts[0]) \(parts[1])", pid: pid, tid: tid, level: level, tag: "", message: rest)
        }
        return LogEntry(
            id: id, timestamp: "\(parts[0]) \(parts[1])", pid: pid, tid: tid, level: level,
            tag: String(rest[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces),
            message: String(rest[colon.upperBound...]))
    }
}

public struct LogFilter: Sendable, Equatable {
    public var minimumLevel: LogLevel = .verbose
    public var text: String = ""
    public var tag: String = ""
    public var pid: Int?

    public init(minimumLevel: LogLevel = .verbose, text: String = "", tag: String = "", pid: Int? = nil) {
        self.minimumLevel = minimumLevel
        self.text = text
        self.tag = tag
        self.pid = pid
    }

    public func matches(_ entry: LogEntry) -> Bool {
        if entry.level < minimumLevel { return false }
        if let pid, entry.pid != pid { return false }
        if !tag.isEmpty, !entry.tag.localizedCaseInsensitiveContains(tag) { return false }
        if !text.isEmpty,
            !entry.message.localizedCaseInsensitiveContains(text), !entry.tag.localizedCaseInsensitiveContains(text)
        {
            return false
        }
        return true
    }
}

public enum DropBoxTag: String, Sendable, CaseIterable, Codable {
    case appCrash = "data_app_crash"
    case appANR = "data_app_anr"
    case appNativeCrash = "data_app_native_crash"
    case systemAppCrash = "system_app_crash"
    case systemServerCrash = "system_server_crash"
    case strictMode = "data_app_strictmode"
}

extension AdbClient {
    /// Streams parsed log entries until cancelled. `backlog` lines are replayed first (`logcat -T`).
    public func logStream(serial: String, backlog: Int = 500, buffers: String = "main,system,crash") -> AsyncThrowingStream<LogEntry, Error> {
        let process = shellStream(serial: serial, "logcat -v threadtime -b \(buffers) -T \(backlog)")
        return AsyncThrowingStream { continuation in
            let task = Task {
                var pending = Data()
                var counter = 0
                do {
                    for try await event in process.events {
                        guard case .stdout(let chunk) = event else { continue }
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 0x0A) {
                            let lineData = pending[pending.startIndex..<newline]
                            pending.removeSubrange(pending.startIndex...newline)
                            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .newlines)
                            counter += 1
                            if let entry = LogParser.parse(line: line, id: counter) { continuation.yield(entry) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                process.cancel()
                task.cancel()
            }
        }
    }

    public func clearLog(serial: String) throws {
        try run(serial: serial, "logcat -b all -c")
    }

    /// Recent entries from Android's crash/ANR dropbox, as text.
    public func dropBox(serial: String, tag: DropBoxTag) throws -> String {
        try shell(serial: serial, "dumpsys dropbox --print \(tag.rawValue)").stdout
    }

    /// `dumpsys` text, capped at `limit` bytes on the device so a full dump cannot exhaust memory.
    /// Use `collectDiagnostics` (which streams to disk) when the whole dump is needed.
    public func dumpsys(serial: String, service: String? = nil, limit: Int = 2_000_000) throws -> String {
        let command = (service.map { "dumpsys \(SettingChange.shellQuote($0))" } ?? "dumpsys") + " | head -c \(limit)"
        return try shell(serial: serial, command).stdout
    }

    public func systemServices(serial: String) throws -> [String] {
        try run(serial: serial, "service list")
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                // "12  activity: [android.app.IActivityManager]"
                let parts = line.split(separator: "\t")
                guard let name = parts.dropFirst().first?.split(separator: ":").first else { return nil }
                return String(name)
            }
            .sorted()
    }

    public func properties(serial: String) throws -> [String: String] {
        DeviceInfoDetails.parseGetprop(try shell(serial: serial, "getprop").stdout.split(separator: "\n", omittingEmptySubsequences: true))
    }

    /// Runs `bugreportz` and downloads the zip. `progress` is 0…100.
    @discardableResult
    public func bugReport(
        serial: String, to directory: URL, progress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = shellStream(serial: serial, "bugreportz -p")
        var output = ""
        for try await event in process.events {
            guard case .stdout(let data) = event else { continue }
            output += String(decoding: data, as: UTF8.self)
            if let range = output.range(of: #"PROGRESS:(\d+)/(\d+)"#, options: [.regularExpression, .backwards]) {
                let numbers = output[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if numbers.count == 2, numbers[1] > 0 { progress?(numbers[0] * 100 / numbers[1]) }
            }
        }
        if let failure = output.range(of: "FAIL:") {
            throw AdbError.adbFailure(String(output[failure.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let ok = output.range(of: "OK:") else { throw AdbError.adbFailure("bugreportz did not return a path: \(output)") }
        let remote = output[ok.upperBound...].split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !remote.isEmpty else { throw AdbError.adbFailure("bugreportz returned an empty path.") }
        let local = try pull(serial: serial, remote: remote, toDirectory: directory)
        _ = try? shell(serial: serial, "rm -f \(SettingChange.shellQuote(remote))")
        return local
    }

    /// Collects diagnostic files: properties, a log snapshot, dumpsys,
    /// crash/ANR dropbox entries, a screenshot — and optionally a full bugreport.
    @discardableResult
    public func collectDiagnostics(
        serial: String, to directory: URL, includeBugReport: Bool = false,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> URL {
        let folder = directory.appendingPathComponent("diagnostics-\(serial)-\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func save(_ name: String, _ text: String) throws {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        progress?("getprop")
        try save("getprop.txt", try shell(serial: serial, "getprop").stdout)
        progress?("logcat")
        try await shellToFile(serial: serial, "logcat -d -v threadtime -b all", to: folder.appendingPathComponent("logcat.txt"))
        progress?("dumpsys")
        try await shellToFile(serial: serial, "dumpsys", to: folder.appendingPathComponent("dumpsys.txt"))
        for tag in DropBoxTag.allCases {
            let text = try dropBox(serial: serial, tag: tag)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try save("dropbox-\(tag.rawValue).txt", text) }
        }
        progress?("screenshot")
        if let png = try? screenshot(serial: serial) { try png.write(to: folder.appendingPathComponent("screenshot.png")) }
        if includeBugReport {
            progress?("bugreport")
            try await bugReport(serial: serial, to: folder)
        }
        return folder
    }
}
