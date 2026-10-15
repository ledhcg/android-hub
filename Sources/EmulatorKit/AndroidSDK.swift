import Foundation

/// Locates the Android SDK pieces the emulator tooling needs.
public struct AndroidSDK: Sendable, Equatable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> AndroidSDK? {
        let candidates =
            [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"], NSHomeDirectory() + "/Library/Android/sdk"]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0 + "/platform-tools") })
            .map { AndroidSDK(root: URL(fileURLWithPath: $0)) }
    }

    public var emulator: URL { root.appendingPathComponent("emulator/emulator") }
    public var adb: URL { root.appendingPathComponent("platform-tools/adb") }
    public var systemImagesDirectory: URL { root.appendingPathComponent("system-images") }

    public var avdmanager: URL? { commandLineTool("avdmanager") }
    public var sdkmanager: URL? { commandLineTool("sdkmanager") }

    /// `cmdline-tools/latest` first, then the newest numbered directory.
    private func commandLineTool(_ name: String) -> URL? {
        let base = root.appendingPathComponent("cmdline-tools")
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
            .sorted { lhs, rhs in
                if lhs == "latest" { return true }
                if rhs == "latest" { return false }
                return lhs.compare(rhs, options: .numeric) == .orderedDescending
            }
        for version in versions {
            let tool = base.appendingPathComponent("\(version)/bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: tool.path) { return tool }
        }
        return nil
    }

    /// The AVD home directory (`ANDROID_AVD_HOME`, `ANDROID_USER_HOME/avd` or `~/.android/avd`).
    public static func avdHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["ANDROID_AVD_HOME"], !explicit.isEmpty { return URL(fileURLWithPath: explicit) }
        if let user = environment["ANDROID_USER_HOME"], !user.isEmpty {
            return URL(fileURLWithPath: user).appendingPathComponent("avd")
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.android/avd")
    }

    /// `avdmanager`/`sdkmanager` are Java programs; GUI apps inherit a bare PATH, so find a JDK explicitly.
    public static func javaHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let home = environment["JAVA_HOME"], FileManager.default.isExecutableFile(atPath: home + "/bin/java") { return home }
        let candidates = [
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
            "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0 + "/bin/java") }) { return found }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !output.isEmpty ? output : nil
    }
}
