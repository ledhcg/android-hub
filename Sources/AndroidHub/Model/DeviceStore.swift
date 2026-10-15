import AdbKit
import AppKit
import EmulatorKit
import Foundation

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case physical = "Thiết bị thật"
    case emulators = "Emulator"
    var id: String { rawValue }
}

enum SidebarSort: String, CaseIterable, Identifiable {
    case name = "Tên"
    case status = "Trạng thái"
    var id: String { rawValue }
}

/// One row in the sidebar: an attached device or an AVD that is not running yet.
enum SidebarItem: Identifiable {
    case device(Device)
    case avd(AVD)

    var id: String {
        switch self {
        case .device(let device): device.serial
        case .avd(let avd): "avd:\(avd.name)"
        }
    }
}

/// App-wide state: attached devices, AVDs, the selection and per-device controllers.
@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var avds: [AVD] = []
    @Published private(set) var runningAVDNames: [String: String] = [:]  // serial → AVD name
    @Published private(set) var startingAVDs: Set<String> = []
    @Published var selection: String? {
        didSet {
            if ProcessInfo.processInfo.environment["ADBHUB_DEBUG"] != nil, oldValue != selection {
                let stack = Thread.callStackSymbols.prefix(8).joined(separator: "\n   ")
                FileHandle.standardError.write(Data("[selection] \(oldValue ?? "nil") → \(selection ?? "nil")\n   \(stack)\n".utf8))
            }
        }
    }
    @Published var filter: SidebarFilter = .all
    @Published var sort: SidebarSort = .name
    @Published var searchText = ""
    @Published var alert: AlertMessage?
    @Published private(set) var adbError: String?

    let client = AdbClient()
    let avdManager: AvdManager?
    private var controllers: [String: MirrorController] = [:]
    private var trackingTask: Task<Void, Never>?

    init() {
        avdManager = try? AvdManager.makeDefault()
        refreshAVDs()
        startTracking()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllers.values.forEach { $0.shutdownBlocking() } }
        }
    }

    // MARK: Tracking

    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [client] in
            while !Task.isCancelled {
                do {
                    for try await list in client.trackDevices() {
                        self.devices = list
                        self.adbError = nil
                        self.refreshRunningEmulators()
                    }
                } catch {
                    self.adbError = error.userMessage
                }
                // The adb server restarted or is unreachable: retry gently.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refreshAVDs() {
        guard let manager = avdManager else { return }
        Task {
            avds = (try? await offMain { try manager.listAVDs() }) ?? []
            refreshRunningEmulators()
        }
    }

    private func refreshRunningEmulators() {
        guard let manager = avdManager else { return }
        let client = self.client
        Task {
            let running = (try? await offMain { try manager.runningEmulators(client: client) }) ?? [:]
            runningAVDNames = running
            startingAVDs.subtract(running.values)
        }
    }

    // MARK: Sidebar content

    func items() -> [SidebarItem] {
        var result: [SidebarItem] = devices.map(SidebarItem.device)
        let runningNames = Set(runningAVDNames.values)
        result += avds.filter { !runningNames.contains($0.name) }.map(SidebarItem.avd)

        switch filter {
        case .all: break
        case .physical: result = result.filter { if case .device(let d) = $0 { d.connection != .emulator } else { false } }
        case .emulators:
            result = result.filter {
                switch $0 {
                case .device(let d): d.connection == .emulator
                case .avd: true
                }
            }
        }
        if !searchText.isEmpty {
            result = result.filter { name(of: $0).localizedCaseInsensitiveContains(searchText) }
        }
        return result.sorted { lhs, rhs in
            if sort == .status, rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return name(of: lhs).localizedStandardCompare(name(of: rhs)) == .orderedAscending
        }
    }

    func name(of item: SidebarItem) -> String {
        switch item {
        case .device(let device):
            if device.connection == .emulator, let avd = runningAVDNames[device.serial] { return avd.replacingOccurrences(of: "_", with: " ") }
            return device.displayName
        case .avd(let avd): return avd.displayName
        }
    }

    private func rank(_ item: SidebarItem) -> Int {
        switch item {
        case .device(let device): device.isReady ? 0 : 1
        case .avd: 2
        }
    }

    var selectedDevice: Device? { devices.first { $0.serial == selection } }
    var selectedAVD: AVD? { selection.flatMap { id in avds.first { "avd:\($0.name)" == id } } }

    func controller(for serial: String) -> MirrorController {
        if let existing = controllers[serial] { return existing }
        let created = MirrorController(serial: serial, client: client)
        controllers[serial] = created
        return created
    }

    // MARK: Actions

    func report(_ error: Error, title: String) {
        alert = AlertMessage(title: title, message: error.userMessage)
    }

    func start(avd: AVD, options: EmulatorLaunchOptions = EmulatorLaunchOptions()) {
        guard let manager = avdManager else { return }
        startingAVDs.insert(avd.name)
        Task {
            do {
                let launched = try await offMain { try manager.start(name: avd.name, options: options) }
                let serial = try await manager.waitUntilBooted(name: avd.name, launched: launched, timeout: 300)
                refreshRunningEmulators()
                selection = serial
            } catch {
                startingAVDs.remove(avd.name)
                report(error, title: "Không khởi động được \(avd.displayName)")
            }
        }
    }

    func stopEmulator(serial: String) {
        guard let manager = avdManager else { return }
        controllers[serial]?.stop()
        let client = self.client
        Task {
            do { try await offMain { try manager.stop(serial: serial, client: client) } } catch {
                report(error, title: "Không tắt được emulator")
            }
        }
    }

    func wipe(avd: AVD) {
        guard let manager = avdManager else { return }
        Task {
            do { try await offMain { try manager.wipeData(name: avd.name) } } catch { report(error, title: "Không xoá được dữ liệu") }
        }
    }

    func delete(avd: AVD) {
        guard let manager = avdManager else { return }
        Task {
            do {
                try await offMain { try manager.deleteAVD(name: avd.name) }
                if selection == "avd:\(avd.name)" { selection = nil }
                refreshAVDs()
            } catch { report(error, title: "Không xoá được AVD") }
        }
    }

    func disconnect(device: Device) {
        let client = self.client
        Task {
            do { try await offMain { try client.disconnect(address: device.serial) } } catch {
                report(error, title: "Không ngắt kết nối được")
            }
        }
    }
}
