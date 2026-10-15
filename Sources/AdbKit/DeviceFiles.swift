import Foundation

/// What to do when a download's destination already exists.
public enum ConflictPolicy: Sendable {
    /// Replace it (atomically — a failed transfer never leaves a half-written file).
    case overwrite
    /// Keep it and write `name 2`, `name 3`, …
    case uniquify
    /// Fail without touching anything.
    case refuse
}

extension URL {
    /// Applies a conflict policy to a download destination.
    public func resolved(policy: ConflictPolicy) throws -> URL {
        if policy == .refuse, FileManager.default.fileExists(atPath: path) {
            throw AdbError.adbFailure("'\(lastPathComponent)' already exists at the destination (use --force to overwrite).")
        }
        return uniqueIfExists(policy: policy)
    }

    /// `dir/name`, or `dir/name 2.ext` etc. when that already exists (only for `.uniquify`).
    public func uniqueIfExists(policy: ConflictPolicy) -> URL {
        guard policy == .uniquify, FileManager.default.fileExists(atPath: path) else { return self }
        let base = deletingPathExtension().lastPathComponent
        let ext = pathExtension
        let directory = deletingLastPathComponent()
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}

/// File management on the device.
extension AdbClient {
    /// Paths whose recursive deletion is never what anyone meant.
    private static let protectedRemotePaths: Set<String> = [
        "/", "/sdcard", "/storage", "/storage/emulated", "/storage/emulated/0", "/data", "/data/data", "/data/local",
        "/system", "/vendor", "/product", "/sdcard/Android", "/storage/emulated/0/Android",
    ]

    public func listDirectory(serial: String, path: String) throws -> [RemoteFileEntry] {
        let session = try syncSession(serial: serial)
        let entries = try session.list(path)
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public func statFile(serial: String, path: String) throws -> RemoteFileEntry? {
        try syncSession(serial: serial).stat(path)
    }

    /// Downloads a file or (recursively) a directory into `directory`; returns the local URL.
    @discardableResult
    public func pull(
        serial: String, remote: String, toDirectory directory: URL, conflict: ConflictPolicy = .overwrite,
        progress: (@Sendable (UInt64) -> Void)? = nil
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try syncSession(serial: serial)
        guard let entry = try session.stat(remote) else { throw AdbError.adbFailure("'\(remote)' not found on the device.") }
        let name = (remote as NSString).lastPathComponent
        let destination = try directory.appendingPathComponent(name.isEmpty ? "root" : name).resolved(policy: conflict)
        if entry.isDirectory {
            try pullDirectory(session: session, remote: remote, local: destination, progress: progress)
        } else {
            try session.pull(remote, to: destination, progress: progress)
        }
        return destination
    }

    private func pullDirectory(
        session: AdbSyncSession, remote: String, local: URL, progress: (@Sendable (UInt64) -> Void)?
    ) throws {
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        for entry in try session.list(remote) {
            let childRemote = (remote as NSString).appendingPathComponent(entry.name)
            let childLocal = local.appendingPathComponent(entry.name)
            if entry.isDirectory {
                try pullDirectory(session: session, remote: childRemote, local: childLocal, progress: progress)
            } else if entry.isRegularFile {
                try session.pull(childRemote, to: childLocal, progress: progress)
            }
        }
    }

    /// Uploads a file or directory into the remote directory `remoteDirectory`.
    public func push(
        serial: String, local: URL, toDirectory remoteDirectory: String,
        progress: (@Sendable (UInt64, UInt64) -> Void)? = nil
    ) throws {
        let session = try syncSession(serial: serial)
        try pushItem(session: session, local: local, remote: (remoteDirectory as NSString).appendingPathComponent(local.lastPathComponent), progress: progress)
    }

    private func pushItem(
        session: AdbSyncSession, local: URL, remote: String, progress: (@Sendable (UInt64, UInt64) -> Void)?
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: local.path, isDirectory: &isDirectory) else {
            throw AdbError.adbFailure("Local file not found: '\(local.path)'.")
        }
        if isDirectory.boolValue {
            // The sync SEND service creates parent directories implicitly on modern adbd, but an empty
            // directory needs an explicit mkdir; do it through a throwaway marker-free approach in shell.
            let children = try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)
            for child in children {
                try pushItem(
                    session: session, local: child, remote: (remote as NSString).appendingPathComponent(child.lastPathComponent),
                    progress: progress)
            }
        } else {
            try session.push(local, to: remote, progress: progress)
        }
    }

    public func makeDirectory(serial: String, path: String) throws {
        try run(serial: serial, "mkdir -p \(SettingChange.shellQuote(path))")
    }

    public func deleteFile(serial: String, path: String, recursive: Bool = true) throws {
        var normalized = path
        while normalized.count > 1, normalized.hasSuffix("/") { normalized.removeLast() }
        guard !normalized.isEmpty, !Self.protectedRemotePaths.contains(normalized) else {
            throw AdbError.adbFailure("Refusing to delete '\(path)': it is a system or storage root directory.")
        }
        try run(serial: serial, "rm \(recursive ? "-rf" : "-f") \(SettingChange.shellQuote(path))")
    }

    public func renameFile(serial: String, from: String, to: String) throws {
        // `mv` silently replaces an existing target; refuse instead of destroying data.
        if try syncSession(serial: serial).stat(to) != nil {
            throw AdbError.adbFailure("An item named '\((to as NSString).lastPathComponent)' already exists at the destination.")
        }
        try run(serial: serial, "mv \(SettingChange.shellQuote(from)) \(SettingChange.shellQuote(to))")
    }

    /// PNG of the primary display at full device resolution.
    public func screenshot(serial: String) throws -> Data {
        let data = try shellData(serial: serial, "screencap -p")
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            throw AdbError.adbFailure("`screencap` did not return a valid PNG (the screen may be protected by a secure lock).")
        }
        return data
    }
}
