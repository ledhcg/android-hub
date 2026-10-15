import AdbKit
import Foundation

public struct AVD: Sendable, Equatable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let directory: String
    public let deviceDefinition: String?
    public let apiTarget: String?
    public let tag: String?
    public let abi: String?
    public let hasPlayStore: Bool
    public let width: Int?
    public let height: Int?
    public let density: Int?
    public let ramMegabytes: Int?
    public let systemImage: String?
}

public struct SystemImage: Sendable, Equatable, Codable, Identifiable {
    public var id: String { packageId }
    /// `system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a`
    public let packageId: String
    public let api: String
    public let tag: String
    public let abi: String
    public let description: String?
}

public struct EmulatorLaunchOptions: Sendable, Equatable {
    public var headless = false
    public var coldBoot = false
    public var wipeData = false
    public var noAudio = true
    public var noSnapshotSave = true
    public var extraArguments: [String] = []
    public init(headless: Bool = false, coldBoot: Bool = false, wipeData: Bool = false, noAudio: Bool = true, noSnapshotSave: Bool = true, extraArguments: [String] = []) {
        self.headless = headless
        self.coldBoot = coldBoot
        self.wipeData = wipeData
        self.noAudio = noAudio
        self.noSnapshotSave = noSnapshotSave
        self.extraArguments = extraArguments
    }

    var arguments: [String] {
        var arguments: [String] = []
        if headless { arguments.append("-no-window") }
        if coldBoot { arguments.append("-no-snapshot-load") }
        if wipeData { arguments.append("-wipe-data") }
        if noAudio { arguments.append("-no-audio") }
        if noSnapshotSave { arguments.append("-no-snapshot-save") }
        return arguments + extraArguments
    }
}

public enum EmulatorError: Error, CustomStringConvertible, Equatable {
    case sdkNotFound
    case toolMissing(String)
    case javaMissing
    case commandFailed(String)
    case notFound(String)
    case bootTimeout(String)
    case stillRunning(String)
    case exitedEarly(String)

    public var description: String {
        switch self {
        case .sdkNotFound: "Android SDK not found. Set ANDROID_HOME or install it via Android Studio."
        case .toolMissing(let tool): "Missing tool '\(tool)'. Install 'Android SDK Command-line Tools' in the SDK Manager."
        case .javaMissing: "JDK not found (avdmanager/sdkmanager require Java). Install Android Studio or set JAVA_HOME."
        case .commandFailed(let message): message
        case .notFound(let name): "AVD '\(name)' not found."
        case .bootTimeout(let name): "Emulator '\(name)' did not finish booting within the timeout."
        case .stillRunning(let name): "AVD '\(name)' is running. Shut down the emulator first."
        case .exitedEarly(let detail): "The emulator exited right after launch.\n\(detail)"
        }
    }
}

/// Create, start, stop and delete Android Virtual Devices.
public struct AvdManager: Sendable {
    public let sdk: AndroidSDK
    public let avdHome: URL

    public init(sdk: AndroidSDK, avdHome: URL = AndroidSDK.avdHome()) {
        self.sdk = sdk
        self.avdHome = avdHome
    }

    public static func makeDefault() throws -> AvdManager {
        guard let sdk = AndroidSDK.locate() else { throw EmulatorError.sdkNotFound }
        return AvdManager(sdk: sdk)
    }

    // MARK: Listing (pure file parsing — no Java needed)

    public func listAVDs() throws -> [AVD] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: avdHome.path)) ?? []
        return files.filter { $0.hasSuffix(".ini") }.compactMap { file -> AVD? in
            let name = String(file.dropLast(4))
            let ini = Self.parseIni((try? String(contentsOf: avdHome.appendingPathComponent(file), encoding: .utf8)) ?? "")
            let directory = ini["path"] ?? avdHome.appendingPathComponent("\(name).avd").path
            let config = Self.parseIni((try? String(contentsOfFile: directory + "/config.ini", encoding: .utf8)) ?? "")
            return Self.makeAVD(name: name, directory: directory, ini: ini, config: config)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func makeAVD(name: String, directory: String, ini: [String: String], config: [String: String]) -> AVD {
        let imageDir = config["image.sysdir.1"]?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let imagePackage = imageDir.map { $0.replacingOccurrences(of: "/", with: ";") }
        // `avdmanager` can write a bogus `target=android-0` for images with a minor version (android-37.0);
        // the system-image path is authoritative: system-images/<api>/<tag>/<abi>.
        let sysdirParts = imageDir?.split(separator: "/").map(String.init) ?? []
        let apiFromImage = sysdirParts.count >= 2 ? sysdirParts[1] : nil
        let declaredTarget = ini["target"] ?? config["target"]
        let apiTarget = declaredTarget == "android-0" || declaredTarget == nil ? (apiFromImage ?? declaredTarget) : declaredTarget
        return AVD(
            name: name, displayName: config["avd.ini.displayname"] ?? name, directory: directory,
            deviceDefinition: config["hw.device.name"], apiTarget: apiTarget,
            tag: config["tag.id"], abi: config["abi.type"], hasPlayStore: config["PlayStore.enabled"] == "true",
            width: config["hw.lcd.width"].flatMap(Int.init), height: config["hw.lcd.height"].flatMap(Int.init),
            density: config["hw.lcd.density"].flatMap(Int.init), ramMegabytes: config["hw.ramSize"].flatMap(Int.init),
            systemImage: imagePackage)
    }

    static func parseIni(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            result[line[..<equals].trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    public func installedSystemImages() -> [SystemImage] {
        var images: [SystemImage] = []
        let fm = FileManager.default
        for api in (try? fm.contentsOfDirectory(atPath: sdk.systemImagesDirectory.path)) ?? [] {
            for tag in (try? fm.contentsOfDirectory(atPath: sdk.systemImagesDirectory.appendingPathComponent(api).path)) ?? [] {
                for abi in (try? fm.contentsOfDirectory(atPath: sdk.systemImagesDirectory.appendingPathComponent("\(api)/\(tag)").path)) ?? []
                where !abi.hasPrefix(".") {
                    let properties = Self.parseIni(
                        (try? String(contentsOf: sdk.systemImagesDirectory.appendingPathComponent("\(api)/\(tag)/\(abi)/source.properties"), encoding: .utf8)) ?? "")
                    images.append(
                        SystemImage(packageId: "system-images;\(api);\(tag);\(abi)", api: api, tag: tag, abi: abi, description: properties["Pkg.Desc"]))
                }
            }
        }
        return images.sorted { $0.packageId.localizedStandardCompare($1.packageId) == .orderedAscending }
    }

    // MARK: avdmanager / sdkmanager

    public func deviceDefinitions() throws -> [String] {
        try runJavaTool(sdk.avdmanager, name: "avdmanager", arguments: ["list", "device", "-c"])
            .split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    @discardableResult
    public func createAVD(name: String, device: String, systemImage: String, force: Bool = false) throws -> AVD {
        var arguments = ["create", "avd", "-n", name, "-k", systemImage, "-d", device]
        if force { arguments.append("--force") }
        // avdmanager asks "Do you wish to create a custom hardware profile?" — answer no.
        _ = try runJavaTool(sdk.avdmanager, name: "avdmanager", arguments: arguments, stdin: "no\n")
        guard let created = try listAVDs().first(where: { $0.name == name }) else {
            throw EmulatorError.commandFailed("avdmanager could not create AVD '\(name)'.")
        }
        return created
    }

    public func deleteAVD(name: String) throws {
        if let avd = try listAVDs().first(where: { $0.name == name }), isRunning(avd) { throw EmulatorError.stillRunning(name) }
        _ = try runJavaTool(sdk.avdmanager, name: "avdmanager", arguments: ["delete", "avd", "-n", name])
    }

    public func renameAVD(from: String, to: String) throws {
        _ = try runJavaTool(sdk.avdmanager, name: "avdmanager", arguments: ["move", "avd", "-n", from, "-r", to])
    }

    /// Downloads a system image. Licences are never accepted automatically; run `sdkmanager --licenses` once.
    public func installSystemImage(_ packageId: String) throws {
        _ = try runJavaTool(sdk.sdkmanager, name: "sdkmanager", arguments: ["--install", packageId])
    }

    private func runJavaTool(_ tool: URL?, name: String, arguments: [String], stdin: String? = nil) throws -> String {
        guard let tool else { throw EmulatorError.toolMissing(name) }
        guard let java = AndroidSDK.javaHome() else { throw EmulatorError.javaMissing }
        var environment = ProcessInfo.processInfo.environment
        environment["JAVA_HOME"] = java
        environment["ANDROID_AVD_HOME"] = avdHome.path
        let result = try Self.run(tool, arguments: arguments, environment: environment, stdin: stdin)
        guard result.status == 0 else {
            throw EmulatorError.commandFailed((result.output.isEmpty ? "\(name) exited with code \(result.status)" : result.output).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output
    }

    static func run(_ executable: URL, arguments: [String], environment: [String: String], stdin: String?) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input = Pipe()
        process.standardInput = input
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: Running emulators

    /// An emulator process started by `start`. Keep it around to notice an early exit.
    public final class LaunchedEmulator: @unchecked Sendable {
        public let process: Process
        public let logURL: URL

        init(process: Process, logURL: URL) {
            self.process = process
            self.logURL = logURL
        }

        public var processIdentifier: Int32 { process.processIdentifier }
        public var isRunning: Bool { process.isRunning }

        /// Exit status plus the end of the emulator's own log, once it has exited.
        public var failureDetail: String? {
            guard !process.isRunning else { return nil }
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let tail = log.split(whereSeparator: \.isNewline).suffix(8).joined(separator: "\n")
            return "Exit code \(process.terminationStatus). Log: \(logURL.path)\n\(tail)"
        }
    }

    /// Starts an emulator in the background; boot continues asynchronously.
    @discardableResult
    public func start(name: String, options: EmulatorLaunchOptions = EmulatorLaunchOptions(), logDirectory: URL? = nil) throws -> LaunchedEmulator {
        guard let avd = try listAVDs().first(where: { $0.name == name }) else { throw EmulatorError.notFound(name) }
        if isRunning(avd) { throw EmulatorError.stillRunning(name) }
        let process = Process()
        process.executableURL = sdk.emulator
        process.arguments = ["-avd", name] + options.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ANDROID_AVD_HOME"] = avdHome.path
        process.environment = environment

        let logURL = (logDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent("emulator-\(name).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return LaunchedEmulator(process: process, logURL: logURL)
    }

    /// Whether this AVD's emulator process is alive. The emulator keeps `hardware-qemu.ini.lock` holding its pid.
    public func isRunning(_ avd: AVD) -> Bool {
        let lock = URL(fileURLWithPath: avd.directory).appendingPathComponent("hardware-qemu.ini.lock")
        guard let raw = try? String(contentsOf: lock, encoding: .utf8) else { return false }
        let digits = raw.filter(\.isNumber)
        guard let pid = Int32(digits), pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// The AVD name behind each running `emulator-NNNN` serial. One emulator whose console cannot be
    /// reached (auth failure, still booting) never hides the others.
    public func runningEmulators(client: AdbClient = AdbClient()) throws -> [String: String] {
        var result: [String: String] = [:]
        for device in try client.devices(enrichWithUSB: false) where device.connection == .emulator && device.state == .device {
            guard let reply = try? client.emulatorCommand(serial: device.serial, "avd name"),
                let name = reply.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0 != "OK" && !$0.isEmpty })
            else { continue }
            result[device.serial] = name
        }
        return result
    }

    /// Polls until the emulator for `name` has finished booting; returns its adb serial. Passing the
    /// `LaunchedEmulator` makes an emulator that dies at launch fail immediately with its log instead of timing out.
    public func waitUntilBooted(
        name: String, launched: LaunchedEmulator? = nil, timeout: TimeInterval = 240, client: AdbClient = AdbClient()
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let launched, let detail = launched.failureDetail { throw EmulatorError.exitedEarly(detail) }
            if let serial = try runningEmulators(client: client).first(where: { $0.value == name })?.key,
                (try? client.run(serial: serial, "getprop sys.boot_completed")) == "1"
            {
                return serial
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw EmulatorError.bootTimeout(name)
    }

    public func stop(serial: String, client: AdbClient = AdbClient()) throws {
        try client.emulatorCommand(serial: serial, "kill")
    }

    /// Erases user data on a stopped AVD (a fresh-install state) without deleting the AVD or its SD card.
    public func wipeData(name: String) throws {
        guard let avd = try listAVDs().first(where: { $0.name == name }) else { throw EmulatorError.notFound(name) }
        if isRunning(avd) { throw EmulatorError.stillRunning(name) }
        let fm = FileManager.default
        for entry in ["userdata-qemu.img", "userdata-qemu.img.qcow2", "cache.img.qcow2", "encryptionkey.img.qcow2", "snapshots"] {
            let path = avd.directory + "/" + entry
            if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
        }
    }
}
