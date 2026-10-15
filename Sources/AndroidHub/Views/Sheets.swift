import AdbKit
import EmulatorKit
import SwiftUI

/// Inline output of a sheet: a warning-tinted banner for failures, a selectable mono well otherwise.
private struct SheetLog: View {
    let text: String
    let isError: Bool

    var body: some View {
        if !text.isEmpty {
            if isError {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(text).font(TypeRole.secondary).foregroundStyle(.primary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.md)
                .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: Radius.control, style: .continuous))
                .accessibilityElement(children: .combine)
            } else {
                ScrollView {
                    Text(text).font(TypeRole.mono).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .wellStyle()
            }
        }
    }
}

/// Pair a phone wirelessly (Android 11+ code pairing) or switch a USB phone to Wi-Fi debugging.
struct PairDeviceSheet: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairingAddress = ""
    @State private var code = ""
    @State private var connectAddress = ""
    @State private var services: [MdnsService] = []
    @State private var log = ""
    @State private var failed = false
    @State private var busy = false
    @State private var usbSerial = ""

    private var usbDevices: [Device] { store.devices.filter { $0.connection == .usb && $0.isReady } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Add Device over Wi-Fi").font(TypeRole.title)
            Form {
                Section {
                    Text("On the phone: Settings → Developer options → Wireless debugging → “Pair device with pairing code”.")
                        .font(TypeRole.caption).foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        TextField("IP:pairing port", text: $pairingAddress)
                        TextField("6-digit code", text: $code).frame(width: 100)
                        Button("Pair") { run { try store.client.pair(address: pairingAddress, code: code) } }
                            .disabled(pairingAddress.isEmpty || code.isEmpty || busy)
                    }
                    HStack(spacing: Space.sm) {
                        TextField("IP:connection port (shown on the Wireless debugging screen)", text: $connectAddress)
                        Button("Connect") { run { try store.client.connect(address: connectAddress) } }
                            .disabled(connectAddress.isEmpty || busy)
                    }
                    HStack(spacing: Space.sm) {
                        Button("Discover Automatically (mDNS)") { discover() }.disabled(busy)
                        ForEach(services, id: \.name) { service in
                            Button("\(service.kind == .pairing ? "Pair" : "Connect") \(service.address)") {
                                if service.kind == .pairing { pairingAddress = service.address } else { connectAddress = service.address }
                            }.buttonStyle(.link)
                        }
                    }
                } header: { Text("Android 11 and later — pair with a code") }
                Section {
                    Text("Connect a USB cable, switch adbd to TCP/IP, then unplug the cable. The device and Mac must be on the same Wi-Fi network.")
                        .font(TypeRole.caption).foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        Picker("USB Device", selection: $usbSerial) {
                            Text("Choose…").tag("")
                            ForEach(usbDevices) { Text($0.displayName).tag($0.serial) }
                        }
                        Button("Enable TCP/IP & Connect") { enableTCPIP() }.disabled(usbSerial.isEmpty || busy)
                    }
                } header: { Text("Android 10 and earlier — via USB") }
            }
            .formStyle(.grouped)
            .disabled(busy)
            SheetLog(text: log, isError: failed)
            HStack(spacing: Space.sm) {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }
                    .prominentActionStyle()
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.lg).frame(width: 560)
    }

    private func run(_ work: @escaping @Sendable () throws -> String) {
        busy = true
        Task {
            defer { busy = false }
            do { log = try await offMain(work); failed = false } catch { log = error.userMessage; failed = true }
        }
    }

    private func discover() {
        let client = store.client
        Task {
            do {
                services = try await offMain { try client.discoverWirelessServices() }
                log = services.isEmpty ? "No services found. Turn on “Wireless debugging” on the phone and keep the pairing screen open." : ""
                failed = !log.isEmpty
            } catch { log = error.userMessage; failed = true }
        }
    }

    private func enableTCPIP() {
        let client = store.client
        let serial = usbSerial
        busy = true
        Task {
            defer { busy = false }
            do {
                let result: String = try await offMain {
                    let reply = try client.enableTCPIP(serial: serial)
                    Thread.sleep(forTimeInterval: 2)
                    guard let ip = try client.wifiAddress(serial: serial) else { return reply + "\nCouldn't read the device's Wi-Fi address." }
                    return reply + "\n" + (try client.connect(address: "\(ip):5555"))
                }
                log = result; failed = false
            } catch { log = error.userMessage; failed = true }
        }
    }
}

/// Create a new Android Virtual Device from an installed system image.
struct NewEmulatorSheet: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Pixel_Test"
    @State private var hardware = "pixel_8"
    @State private var image = ""
    @State private var hardwareList: [String] = []
    @State private var images: [SystemImage] = []
    @State private var downloadId = ""
    @State private var log = ""
    @State private var failed = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("New Emulator").font(TypeRole.title)
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Device", selection: $hardware) { ForEach(hardwareList, id: \.self) { Text($0).tag($0) } }
                    Picker("System image", selection: $image) {
                        ForEach(images) { Text($0.packageId.replacingOccurrences(of: "system-images;", with: "")).tag($0.packageId) }
                    }
                }
                Section {
                    if images.isEmpty {
                        Text("No system images yet. Download one using the package ID below (accept the licenses first: `sdkmanager --licenses`).")
                            .font(TypeRole.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: Space.sm) {
                        TextField("Package ID", text: $downloadId, prompt: Text("system-images;android-35;google_apis;arm64-v8a"))
                        Button("Download Image") { download() }.disabled(downloadId.isEmpty || busy)
                    }
                } header: { Text("Download a system image") }
            }
            .formStyle(.grouped)
            .disabled(busy)
            SheetLog(text: log, isError: failed)
            HStack(spacing: Space.sm) {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .prominentActionStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || image.isEmpty || busy)
            }
        }
        .padding(Space.lg).frame(width: 520)
        .task { await load() }
    }

    private func load() async {
        guard let manager = store.avdManager else { log = EmulatorError.sdkNotFound.description; failed = true; return }
        images = manager.installedSystemImages()
        if image.isEmpty { image = images.first?.packageId ?? "" }
        hardwareList = (try? await offMain { try manager.deviceDefinitions() }) ?? ["pixel_8"]
        if !hardwareList.contains(hardware) { hardware = hardwareList.first ?? "pixel_8" }
    }

    private func create() {
        guard let manager = store.avdManager else { return }
        busy = true
        let (name, hardware, image) = (self.name, self.hardware, self.image)
        Task {
            defer { busy = false }
            do {
                _ = try await offMain { try manager.createAVD(name: name, device: hardware, systemImage: image) }
                store.refreshAVDs()
                dismiss()
            } catch { log = error.userMessage; failed = true }
        }
    }

    private func download() {
        guard let manager = store.avdManager else { return }
        busy = true
        let id = downloadId
        Task {
            defer { busy = false }
            do {
                try await offMain { try manager.installSystemImage(id) }
                images = manager.installedSystemImages()
                log = "Installed \(id)"; failed = false
            } catch { log = error.userMessage; failed = true }
        }
    }
}

struct AVDDetailView: View {
    let avd: AVD
    @EnvironmentObject var store: DeviceStore
    @State private var headless = false
    @State private var coldBoot = false
    @State private var wipe = false

    private var starting: Bool { store.startingAVDs.contains(avd.name) }

    var body: some View {
        StatusMessage(symbol: "desktopcomputer", title: avd.displayName, message: "This emulator is not running.") {
            VStack(spacing: Space.lg) {
                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                    row("Device", avd.deviceDefinition)
                    row("API", avd.apiTarget)
                    row("ABI", avd.abi)
                    row("Display", avd.width.flatMap { w in avd.height.map { "\(w)×\($0) @\(avd.density ?? 0)dpi" } })
                    row("RAM", avd.ramMegabytes.map { "\($0) MB" })
                    row("Play Store", avd.hasPlayStore ? "Yes" : "No")
                    row("System image", avd.systemImage)
                }
                .font(TypeRole.secondary)
                if starting {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Starting…").font(TypeRole.secondary).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: Space.sm) {
                        Button("Start") { launch() }
                            .prominentActionStyle().controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                        Menu {
                            Toggle("No Window", isOn: $headless)
                            Toggle("Cold Boot", isOn: $coldBoot)
                            Toggle("Wipe Data", isOn: $wipe)
                        } label: {
                            Label("Start Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(minWidth: 24, minHeight: 24)
                        .help("Start options")
                        .accessibilityLabel("Start options")
                    }
                    .fixedSize()
                }
            }
        }
        .canvasBackground()
    }

    private func launch() {
        store.start(avd: avd, options: EmulatorLaunchOptions(headless: headless, coldBoot: coldBoot, wipeData: wipe))
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value { GridRow { Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing); Text(value).textSelection(.enabled) } }
    }
}
