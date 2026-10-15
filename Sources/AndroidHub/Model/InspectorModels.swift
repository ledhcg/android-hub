import AdbKit
import AppKit
import SwiftUI

/// Base for per-device panels: knows which device it talks to and how to report errors.
@MainActor
class PanelModel: ObservableObject {
    let serial: String
    let client: AdbClient
    @Published var isLoading = false
    @Published var error: String?

    init(serial: String, client: AdbClient) {
        self.serial = serial
        self.client = client
    }

    var isEmulator: Bool { serial.hasPrefix("emulator-") }

    func fail(_ error: Error) { self.error = error.userMessage }
}

// MARK: - Info

@MainActor
final class InfoModel: PanelModel {
    @Published var info: DeviceInfoDetails?
    @Published var properties: [String: String] = [:]
    @Published var showsProperties = false

    func load() {
        isLoading = true
        let (client, serial) = (self.client, self.serial)
        Task {
            defer { isLoading = false }
            do {
                info = try await offMain { try client.deviceInfo(serial: serial) }
                error = nil
            } catch { fail(error) }
        }
    }

    func loadProperties() {
        let (client, serial) = (self.client, self.serial)
        Task {
            do { properties = try await offMain { try client.properties(serial: serial) } } catch { fail(error) }
        }
    }
}

// MARK: - Settings

@MainActor
final class SettingsModel: PanelModel {
    @Published var snapshot = DeviceSettingsSnapshot()
    @Published var info: DeviceInfoDetails?

    func load() {
        isLoading = true
        let (client, serial) = (self.client, self.serial)
        Task {
            defer { isLoading = false }
            do {
                async let snap = offMain { try client.settingsSnapshot(serial: serial) }
                async let details = offMain { try client.deviceInfo(serial: serial) }
                snapshot = try await snap
                info = try await details
                error = nil
            } catch { fail(error) }
        }
    }

    /// Applies a change on the device; `update` mirrors it into the snapshot immediately so controls feel instant.
    func apply(_ change: SettingChange, update: ((inout DeviceSettingsSnapshot) -> Void)? = nil) {
        if let update { update(&snapshot) }
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                try await offMain { try client.apply(change, serial: serial) }
                error = nil
                if case .displaySize = change { refreshDisplay() }
                if case .resetDisplaySize = change { refreshDisplay() }
                if case .displayDensity = change { refreshDisplay() }
                if case .resetDisplayDensity = change { refreshDisplay() }
            } catch {
                fail(error)
                load()  // re-sync with the real device state
            }
        }
    }

    private func refreshDisplay() {
        let (client, serial) = (self.client, self.serial)
        Task { info = try? await offMain { try client.deviceInfo(serial: serial) } }
    }

    func binding<T>(_ keyPath: WritableKeyPath<DeviceSettingsSnapshot, T?>, default fallback: T, change: @escaping (T) -> SettingChange) -> Binding<T> {
        Binding(
            get: { self.snapshot[keyPath: keyPath] ?? fallback },
            set: { newValue in self.apply(change(newValue)) { $0[keyPath: keyPath] = newValue } })
    }
}

// MARK: - Apps

@MainActor
final class AppsModel: PanelModel {
    @Published var apps: [InstalledApp] = []
    @Published var selected: String?
    @Published var details: AppDetails?
    @Published var includeSystem = false
    @Published var search = ""
    @Published var installProgress: String?
    @Published var message: String?
    private var selectGeneration = 0

    var visibleApps: [InstalledApp] {
        apps.filter { (includeSystem || !$0.isSystem) && (search.isEmpty || $0.packageName.localizedCaseInsensitiveContains(search)) }
    }

    func load() {
        isLoading = true
        let (client, serial) = (self.client, self.serial)
        Task {
            defer { isLoading = false }
            do {
                apps = try await offMain { try client.installedApps(serial: serial) }
                error = nil
            } catch { fail(error) }
        }
    }

    func select(_ package: String?) {
        selected = package
        details = nil
        selectGeneration += 1
        let generation = selectGeneration
        guard let package else { return }
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                let loaded = try await offMain { try client.appDetails(serial: serial, package: package) }
                // A slow answer for a previously selected app must not replace the current one's details
                // (the permission toggles would then act on the wrong package).
                if generation == selectGeneration { details = loaded }
            } catch { if generation == selectGeneration { fail(error) } }
        }
    }

    private func run(_ title: String, reload: Bool = false, _ work: @escaping @Sendable (AdbClient, String) throws -> Void) {
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                try await offMain { try work(client, serial) }
                message = title
                error = nil
                if reload { load() }
            } catch { fail(error) }
        }
    }

    func launch(_ package: String) { run("Opened \(package)") { try $0.launchApp(serial: $1, package: package) } }
    func stop(_ package: String) { run("Stopped \(package)") { try $0.forceStopApp(serial: $1, package: package) } }
    func clear(_ package: String) { run("Cleared data for \(package)") { try $0.clearAppData(serial: $1, package: package) } }
    func openInfo(_ package: String) { run("Opened info for \(package)") { try $0.openAppInfo(serial: $1, package: package) } }

    func uninstall(_ package: String) {
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                try await offMain { try client.uninstallApp(serial: serial, package: package) }
                message = "Uninstalled \(package)"
                selected = nil
                details = nil
                load()
            } catch { fail(error) }
        }
    }

    func setPermission(_ permission: String, granted: Bool, package: String) {
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                try await offMain { try client.setPermission(serial: serial, package: package, permission: permission, granted: granted) }
                select(package)
            } catch { fail(error) }
        }
    }

    func install(_ urls: [URL], options: InstallOptions = InstallOptions()) {
        let (client, serial) = (self.client, self.serial)
        installProgress = "Uploading…"
        Task {
            do {
                try await offMain {
                    try client.installApps(serial: serial, apks: urls, options: options) { stage in
                        Task { @MainActor in
                            switch stage {
                            case .uploading(let file, let sent, let total):
                                self.installProgress = "Uploading \(file) \(total > 0 ? Int(sent * 100 / total) : 0)%"
                            case .installing: self.installProgress = "Installing…"
                            case .done: break
                            }
                        }
                    }
                }
                installProgress = nil
                message = "Installed \(urls.map(\.lastPathComponent).joined(separator: ", "))"
                load()
            } catch {
                installProgress = nil
                fail(error)
            }
        }
    }

    func extract(_ package: String, to directory: URL) {
        let (client, serial) = (self.client, self.serial)
        Task {
            do {
                let files = try await offMain { try client.extractApks(serial: serial, package: package, to: directory) }
                message = "Pulled \(files.count) APK file(s)"
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } catch { fail(error) }
        }
    }
}

// MARK: - Files

@MainActor
final class FilesModel: PanelModel {
    /// The address bar. It is editable, so it can differ from what is actually listed.
    @Published var path = "/sdcard"
    /// The directory `entries` really belongs to. Every remote path is built from THIS, never from the
    /// address bar, so a half-typed path can never redirect a delete or a download.
    @Published private(set) var loadedPath = "/sdcard"
    @Published var entries: [RemoteFileEntry] = []
    @Published var selected: Set<String> = []
    @Published var message: String?
    @Published var transfer: String?
    /// When set, browsing happens inside this app's private storage (run-as, debuggable apps only).
    @Published var containerPackage: String?
    private var loadGeneration = 0

    func load(_ newPath: String? = nil) {
        if let newPath { path = newPath }
        selected = []
        isLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        let (client, serial, target, container) = (self.client, self.serial, path, containerPackage)
        Task {
            do {
                let loaded: [RemoteFileEntry]
                if let container {
                    loaded = try await offMain { try client.containerList(serial: serial, package: container, path: target) }
                        .sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                } else {
                    loaded = try await offMain { try client.listDirectory(serial: serial, path: target) }
                }
                // Only the newest request may publish: a slow listing of A must not overwrite B.
                guard generation == loadGeneration else { return }
                entries = loaded
                loadedPath = target
                isLoading = false
                error = nil
            } catch {
                guard generation == loadGeneration else { return }
                isLoading = false
                fail(error)
            }
        }
    }

    func open(_ entry: RemoteFileEntry) {
        if entry.isDirectory { load(join(entry.name)) }
    }

    func goUp() {
        guard loadedPath != "/", loadedPath != "." else { return }
        let parent = (loadedPath as NSString).deletingLastPathComponent
        load(parent.isEmpty ? (containerPackage == nil ? "/" : ".") : parent)
    }

    func join(_ name: String) -> String { (loadedPath as NSString).appendingPathComponent(name) }

    func useContainer(_ package: String?) {
        containerPackage = package
        load(package == nil ? "/sdcard" : ".")
    }

    func pull(_ names: [String], to directory: URL) {
        let (client, serial, container) = (self.client, self.serial, containerPackage)
        let remotes = names.map(join)
        transfer = "Downloading…"
        Task {
            defer { transfer = nil }
            do {
                let results: [URL] = try await offMain {
                    try remotes.map { remote in
                        if let container {
                            let local = directory.appendingPathComponent((remote as NSString).lastPathComponent)
                            let destination = local.uniqueIfExists(policy: .uniquify)
                            try client.containerPull(serial: serial, package: container, path: remote, to: destination)
                            return destination
                        }
                        // Never replace something the user already has: a clash becomes "name 2".
                        return try client.pull(serial: serial, remote: remote, toDirectory: directory, conflict: .uniquify)
                    }
                }
                message = "Downloaded \(results.count) item(s)"
                NSWorkspace.shared.activateFileViewerSelecting(results)
            } catch { fail(error) }
        }
    }

    func push(_ urls: [URL]) {
        guard containerPackage == nil else {
            error = "Pushing files into an app's data container isn't supported; use a shared folder such as /sdcard."
            return
        }
        let (client, serial, path) = (self.client, self.serial, loadedPath)
        transfer = "Uploading…"
        Task {
            defer { transfer = nil }
            do {
                try await offMain { for url in urls { try client.push(serial: serial, local: url, toDirectory: path) } }
                message = "Uploaded \(urls.count) item(s)"
                load(path)
            } catch { fail(error) }
        }
    }

    func delete(_ names: [String]) {
        guard containerPackage == nil else { return }  // the plain shell cannot reach an app's private storage
        let (client, serial) = (self.client, self.serial)
        let remotes = names.map(join)
        Task {
            do {
                try await offMain { for remote in remotes { try client.deleteFile(serial: serial, path: remote) } }
                load(loadedPath)
            } catch { fail(error) }
        }
    }

    func makeFolder(_ name: String) {
        let (client, serial) = (self.client, self.serial)
        let remote = join(name)
        Task {
            do {
                try await offMain { try client.makeDirectory(serial: serial, path: remote) }
                load(loadedPath)
            } catch { fail(error) }
        }
    }

    func rename(_ old: String, to new: String) {
        let (client, serial) = (self.client, self.serial)
        let (from, to) = (join(old), join(new))
        Task {
            do {
                try await offMain { try client.renameFile(serial: serial, from: from, to: to) }
                load(loadedPath)
            } catch { fail(error) }
        }
    }
}

// MARK: - Logs

/// Streams logcat without touching the UI per line: entries are buffered and published a few times a
/// second, already filtered, so a chatty device cannot saturate the main thread.
@MainActor
final class LogsModel: PanelModel {
    @Published private(set) var visible: [LogEntry] = []
    @Published var filter = LogFilter() { didSet { rebuildVisible() } }
    @Published var isPaused = false
    @Published var isStreaming = false

    private var all: [LogEntry] = []
    private var incoming: [LogEntry] = []
    private var held: [LogEntry] = []
    private var streamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var generation = 0
    private let capacity = 5000

    func start() {
        guard !isStreaming else { return }
        isStreaming = true
        generation += 1
        let myGeneration = generation
        let (client, serial) = (self.client, self.serial)
        streamTask = Task {
            do {
                for try await entry in client.logStream(serial: serial, backlog: 300) {
                    guard myGeneration == generation else { return }
                    if isPaused {
                        held.append(entry)
                        if held.count > capacity * 4 { held.removeFirst(held.count - capacity * 4) }
                    } else {
                        incoming.append(entry)
                    }
                }
            } catch { if !Task.isCancelled, myGeneration == generation { fail(error) } }
            // A restarted stream owns the flag; the old task's tail must not clobber it.
            if myGeneration == generation { isStreaming = false }
        }
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                flush()
            }
        }
    }

    func stop() {
        generation += 1
        streamTask?.cancel()
        flushTask?.cancel()
        streamTask = nil
        flushTask = nil
        isStreaming = false
    }

    private func flush() {
        guard !incoming.isEmpty else { return }
        let batch = incoming
        incoming.removeAll(keepingCapacity: true)
        all += batch
        if all.count > capacity { all.removeFirst(all.count - capacity) }
        let matching = batch.filter(filter.matches)
        guard !matching.isEmpty else { return }
        visible += matching
        if visible.count > capacity { visible.removeFirst(visible.count - capacity) }
    }

    private func rebuildVisible() { visible = all.filter(filter.matches) }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            incoming += held
            held.removeAll()
        }
    }

    func clear() {
        all.removeAll()
        incoming.removeAll()
        held.removeAll()
        visible.removeAll()
        let (client, serial) = (self.client, self.serial)
        Task { try? await offMain { try client.clearLog(serial: serial) } }
    }

    func text(for entries: [LogEntry]) -> String {
        entries.map { "\($0.timestamp) \($0.pid)/\($0.tid) \($0.level.rawValue) \($0.tag): \($0.message)" }.joined(separator: "\n")
    }
}

// MARK: - Diagnostics

@MainActor
final class DiagnosticsModel: PanelModel {
    @Published var dropBoxTag: DropBoxTag = .appCrash
    @Published var dropBoxText = ""
    @Published var services: [String] = []
    @Published var selectedService = ""
    @Published var dumpText = ""
    @Published var progress: String?
    @Published var message: String?

    func loadDropBox() {
        let (client, serial, tag) = (self.client, self.serial, dropBoxTag)
        Task {
            do { dropBoxText = try await offMain { try client.dropBox(serial: serial, tag: tag) } } catch { fail(error) }
        }
    }

    func loadServices() {
        let (client, serial) = (self.client, self.serial)
        Task {
            do { services = try await offMain { try client.systemServices(serial: serial) } } catch { fail(error) }
        }
    }

    func dump(_ service: String) {
        let (client, serial) = (self.client, self.serial)
        progress = "Running dumpsys \(service)…"
        Task {
            defer { progress = nil }
            do { dumpText = try await offMain { try client.dumpsys(serial: serial, service: service) } } catch { fail(error) }
        }
    }

    func collect(to directory: URL, includeBugReport: Bool) {
        let (client, serial) = (self.client, self.serial)
        progress = "Collecting…"
        Task {
            defer { progress = nil }
            do {
                let folder = try await client.collectDiagnostics(serial: serial, to: directory, includeBugReport: includeBugReport) { step in
                    Task { @MainActor in self.progress = "Collecting: \(step)…" }
                }
                message = "Saved \(folder.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch { fail(error) }
        }
    }
}
