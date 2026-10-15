import Foundation

public struct InstalledApp: Sendable, Equatable, Codable, Identifiable {
    public var id: String { packageName }
    public let packageName: String
    public let apkPath: String
    public let versionCode: Int?
    public let isSystem: Bool
}

public struct AppPermission: Sendable, Equatable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    /// `nil` when the platform does not report a grant state for it.
    public let granted: Bool?
    /// Runtime (dangerous) permissions can be granted/revoked from the Mac; install-time ones cannot.
    public let isRuntime: Bool
}

public struct AppDetails: Sendable, Equatable, Codable {
    public var packageName: String
    public var versionName: String?
    public var versionCode: Int?
    public var minSdk: Int?
    public var targetSdk: Int?
    public var firstInstall: String?
    public var lastUpdate: String?
    public var installer: String?
    public var userId: Int?
    public var dataDirectory: String?
    public var isDebuggable: Bool
    public var isSystem: Bool
    public var permissions: [AppPermission]
}

public struct InstallOptions: Sendable, Equatable {
    public var replaceExisting = true
    public var allowDowngrade = false
    public var allowTestPackages = true
    public var grantAllPermissions = false
    public init(replaceExisting: Bool = true, allowDowngrade: Bool = false, allowTestPackages: Bool = true, grantAllPermissions: Bool = false) {
        self.replaceExisting = replaceExisting
        self.allowDowngrade = allowDowngrade
        self.allowTestPackages = allowTestPackages
        self.grantAllPermissions = grantAllPermissions
    }

    var flags: String {
        var parts: [String] = []
        if replaceExisting { parts.append("-r") }
        if allowDowngrade { parts.append("-d") }
        if allowTestPackages { parts.append("-t") }
        if grantAllPermissions { parts.append("-g") }
        return parts.joined(separator: " ")
    }
}

public enum InstallStage: Sendable, Equatable {
    case uploading(file: String, sent: UInt64, total: UInt64)
    case installing
    case done
}

// MARK: - Parsing

enum AppParsing {
    /// `package:/data/app/~~x==/com.foo-y==/base.apk=com.foo versionCode:12`
    static func parsePackageList(_ text: String, isSystem: Bool) -> [InstalledApp] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("package:") else { return nil }
            line.removeFirst("package:".count)

            var versionCode: Int?
            if let range = line.range(of: " versionCode:") {
                let tail = line[range.upperBound...].split(separator: " ").first ?? ""
                versionCode = Int(tail)
                line = String(line[..<range.lowerBound])
            }
            // Base64 path components may contain '=', so the separator is the LAST one.
            guard let equals = line.lastIndex(of: "=") else {
                return InstalledApp(packageName: line, apkPath: "", versionCode: versionCode, isSystem: isSystem)
            }
            return InstalledApp(
                packageName: String(line[line.index(after: equals)...]), apkPath: String(line[..<equals]),
                versionCode: versionCode, isSystem: isSystem)
        }
    }

    static func parseDetails(package: String, dumpsys: String) -> AppDetails? {
        let lines = dumpsys.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("Package [\(package)]") }) else { return nil }

        var details = AppDetails(packageName: package, isDebuggable: false, isSystem: false, permissions: [])
        var section = ""
        var sectionIndent = 0
        // Runtime grants are listed per Android user (work profile, Xiaomi Second Space, Dual Apps…);
        // `pm grant` acts on the primary user, so only that block may drive the toggles.
        var currentUser = 0
        var seen: [String: AppPermission] = [:]
        var order: [String] = []

        func record(_ name: String, granted: Bool?, runtime: Bool) {
            if seen[name] == nil { order.append(name) }
            let previous = seen[name]
            seen[name] = AppPermission(
                name: name, granted: granted ?? previous?.granted, isRuntime: runtime || (previous?.isRuntime ?? false))
        }

        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent == 0 { break }  // next top-level dumpsys section
            if indent <= 2 && trimmed.hasPrefix("Package [") { break }  // next package block
            if !section.isEmpty, indent <= sectionIndent { section = "" }

            if trimmed.hasPrefix("User "), let colon = trimmed.firstIndex(of: ":"),
                let user = Int(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<colon])
            {
                currentUser = user
            }

            if trimmed.hasSuffix(":"), !trimmed.contains("=") {
                section = trimmed
                sectionIndent = indent
                continue
            }

            switch section {
            case "requested permissions:":
                record(String(trimmed.split(separator: ":", maxSplits: 1)[0]), granted: nil, runtime: false)
            case "install permissions:":
                if let colon = trimmed.firstIndex(of: ":") {
                    record(String(trimmed[..<colon]), granted: trimmed.contains("granted=true"), runtime: false)
                }
            case "runtime permissions:":
                if currentUser == 0, let colon = trimmed.firstIndex(of: ":") {
                    record(String(trimmed[..<colon]), granted: trimmed.contains("granted=true"), runtime: true)
                }
            default:
                func value(_ key: String) -> String? {
                    trimmed.hasPrefix(key + "=") ? String(trimmed.dropFirst(key.count + 1)) : nil
                }
                if let v = value("versionName") { details.versionName = v }
                if let v = value("versionCode") {
                    details.versionCode = Int(v.split(separator: " ").first ?? "")
                    if let m = trimmed.range(of: #"minSdk=(\d+)"#, options: .regularExpression) {
                        details.minSdk = Int(trimmed[m].dropFirst("minSdk=".count))
                    }
                    if let m = trimmed.range(of: #"targetSdk=(\d+)"#, options: .regularExpression) {
                        details.targetSdk = Int(trimmed[m].dropFirst("targetSdk=".count))
                    }
                }
                if let v = value("firstInstallTime") { details.firstInstall = v }
                if let v = value("lastUpdateTime") { details.lastUpdate = v }
                if let v = value("installerPackageName") { details.installer = v == "null" ? nil : v }
                if let v = value("userId") { details.userId = Int(v.split(separator: " ").first ?? "") }
                if let v = value("dataDir") { details.dataDirectory = v }
                if trimmed.hasPrefix("flags=[") || trimmed.hasPrefix("pkgFlags=[") {
                    details.isDebuggable = details.isDebuggable || trimmed.contains("DEBUGGABLE")
                    details.isSystem = details.isSystem || trimmed.contains("[ SYSTEM") || trimmed.contains(" SYSTEM ")
                }
            }
        }
        details.permissions = order.compactMap { seen[$0] }
        return details
    }

    /// `Success`, `Failure [INSTALL_FAILED_VERSION_DOWNGRADE]` and friends.
    static func installFailure(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { $0.hasPrefix("Success") }) { return nil }
        return lines.last(where: { $0.hasPrefix("Failure") || $0.contains("Exception") }) ?? output
    }
}

// MARK: - Operations

extension AdbClient {
    public func installedApps(serial: String) throws -> [InstalledApp] {
        let script = """
            pm list packages -f --show-versioncode -3 2>/dev/null || pm list packages -f -3
            echo @@SYSTEM@@
            pm list packages -f --show-versioncode -s 2>/dev/null || pm list packages -f -s
            """
        let output = try shell(serial: serial, script).stdout
        let parts = output.components(separatedBy: "@@SYSTEM@@")
        let user = AppParsing.parsePackageList(parts[0], isSystem: false)
        let system = parts.count > 1 ? AppParsing.parsePackageList(parts[1], isSystem: true) : []
        return (user + system).sorted { $0.packageName < $1.packageName }
    }

    public func appDetails(serial: String, package: String) throws -> AppDetails {
        let dump = try shell(serial: serial, "dumpsys package \(SettingChange.shellQuote(package))").stdout
        guard let details = AppParsing.parseDetails(package: package, dumpsys: dump) else {
            throw AdbError.adbFailure("Không tìm thấy gói '\(package)' trên thiết bị.")
        }
        return details
    }

    public func launchApp(serial: String, package: String) throws {
        let quoted = SettingChange.shellQuote(package)
        let resolved = try shell(
            serial: serial, "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER \(quoted)")
        if let component = resolved.stdout.split(whereSeparator: \.isNewline).last.map(String.init),
            component.contains("/"), !component.contains(" ")
        {
            try run(serial: serial, "am start -n \(SettingChange.shellQuote(component))")
        } else {
            try run(serial: serial, "monkey -p \(quoted) -c android.intent.category.LAUNCHER 1")
        }
    }

    public func forceStopApp(serial: String, package: String) throws {
        try run(serial: serial, "am force-stop \(SettingChange.shellQuote(package))")
    }

    public func clearAppData(serial: String, package: String) throws {
        try run(serial: serial, "pm clear \(SettingChange.shellQuote(package))")
    }

    public func uninstallApp(serial: String, package: String, keepData: Bool = false) throws {
        let output = try run(serial: serial, "pm uninstall \(keepData ? "-k " : "")\(SettingChange.shellQuote(package))")
        if !output.contains("Success") { throw AdbError.adbFailure(output) }
    }

    public func setPermission(serial: String, package: String, permission: String, granted: Bool) throws {
        try run(
            serial: serial,
            "pm \(granted ? "grant" : "revoke") \(SettingChange.shellQuote(package)) \(SettingChange.shellQuote(permission))")
    }

    public func openAppInfo(serial: String, package: String) throws {
        try run(
            serial: serial,
            "am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d \(SettingChange.shellQuote("package:" + package))")
    }

    /// Installs one APK, or a set of split APKs (base + config splits) as a single session.
    public func installApps(
        serial: String, apks: [URL], options: InstallOptions = InstallOptions(),
        progress: (@Sendable (InstallStage) -> Void)? = nil
    ) throws {
        guard !apks.isEmpty else { throw AdbError.adbFailure("Không có file APK nào để cài.") }
        let session = try syncSession(serial: serial)
        let token = UUID().uuidString.prefix(8)
        var remotes: [(local: URL, remote: String, size: UInt64)] = []

        defer {
            let paths = remotes.map { SettingChange.shellQuote($0.remote) }.joined(separator: " ")
            if !paths.isEmpty { _ = try? shell(serial: serial, "rm -f \(paths)") }
        }

        for (index, apk) in apks.enumerated() {
            let remote = "/data/local/tmp/androidhub-\(token)-\(index).apk"
            let size = (try FileManager.default.attributesOfItem(atPath: apk.path)[.size] as? UInt64) ?? 0
            remotes.append((apk, remote, size))
            try session.push(apk, to: remote) { sent, total in
                progress?(.uploading(file: apk.lastPathComponent, sent: sent, total: total))
            }
        }

        progress?(.installing)
        if remotes.count == 1 {
            let output = try shell(serial: serial, "pm install \(options.flags) \(SettingChange.shellQuote(remotes[0].remote))")
            if let failure = AppParsing.installFailure(from: output.stdout + output.stderr) { throw AdbError.adbFailure(failure) }
        } else {
            let created = try run(serial: serial, "pm install-create \(options.flags)")
            guard let range = created.range(of: #"\[(\d+)\]"#, options: .regularExpression) else {
                throw AdbError.adbFailure("Không tạo được phiên cài đặt: \(created)")
            }
            let sessionId = created[range].dropFirst().dropLast()
            for (index, item) in remotes.enumerated() {
                try run(
                    serial: serial,
                    "pm install-write -S \(item.size) \(sessionId) split\(index).apk \(SettingChange.shellQuote(item.remote))")
            }
            let output = try shell(serial: serial, "pm install-commit \(sessionId)")
            if let failure = AppParsing.installFailure(from: output.stdout + output.stderr) { throw AdbError.adbFailure(failure) }
        }
        progress?(.done)
    }

    /// Copies every APK of an installed app (base + splits) to `directory`.
    @discardableResult
    public func extractApks(serial: String, package: String, to directory: URL, conflict: ConflictPolicy = .overwrite) throws -> [URL] {
        let paths = try run(serial: serial, "pm path \(SettingChange.shellQuote(package))")
            .split(whereSeparator: \.isNewline)
            .compactMap { $0.hasPrefix("package:") ? String($0.dropFirst("package:".count)) : nil }
        guard !paths.isEmpty else { throw AdbError.adbFailure("Không tìm thấy APK của '\(package)'.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let session = try syncSession(serial: serial)
        return try paths.map { path in
            let destination = try directory.appendingPathComponent((path as NSString).lastPathComponent).resolved(policy: conflict)
            try session.pull(path, to: destination)
            return destination
        }
    }

    // MARK: Data container (debuggable apps only, via run-as)

    public func containerList(serial: String, package: String, path: String = ".") throws -> [RemoteFileEntry] {
        let output = try run(
            serial: serial, "run-as \(SettingChange.shellQuote(package)) ls -la \(SettingChange.shellQuote(path))")
        return Self.parseLsLong(output)
    }

    public func containerRead(serial: String, package: String, path: String) throws -> Data {
        try shellData(serial: serial, "run-as \(SettingChange.shellQuote(package)) cat \(SettingChange.shellQuote(path))")
    }

    public func containerPull(serial: String, package: String, path: String, to local: URL, conflict: ConflictPolicy = .overwrite) throws {
        let destination = try local.resolved(policy: conflict)
        try containerRead(serial: serial, package: package, path: path).write(to: destination, options: .atomic)
    }

    /// Writes `data` to a file inside the app's private storage.
    public func containerWrite(serial: String, package: String, path: String, data: Data) throws {
        let staging = "/data/local/tmp/androidhub-\(UUID().uuidString.prefix(8)).tmp"
        try syncSession(serial: serial).push(data, to: staging, mode: 0o100666)
        defer { _ = try? shell(serial: serial, "rm -f \(staging)") }
        try run(
            serial: serial,
            "run-as \(SettingChange.shellQuote(package)) sh -c \(SettingChange.shellQuote("cat \(staging) > \(SettingChange.shellQuote(path))"))")
    }

    /// Parses `ls -la` output (toybox format): `-rw-rw---- 1 u0_a123 u0_a123 4096 2024-01-01 10:00 name`.
    static func parseLsLong(_ text: String) -> [RemoteFileEntry] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let tokens = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 8, tokens[0].count >= 10 else { return nil }
            let permissions = tokens[0]
            var mode: UInt32 = 0
            switch permissions.first {
            case "d": mode |= 0o040000
            case "l": mode |= 0o120000
            default: mode |= 0o100000
            }
            let bits = Array(permissions.dropFirst().prefix(9))
            for (index, bit) in bits.enumerated() where bit != "-" { mode |= 1 << UInt32(8 - index) }
            var name = tokens[7]
            if let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            if name == "." || name == ".." { return nil }
            return RemoteFileEntry(
                name: name, mode: mode, size: UInt64(tokens[4]) ?? 0,
                modified: formatter.date(from: "\(tokens[5]) \(tokens[6])") ?? Date(timeIntervalSince1970: 0))
        }
    }
}
