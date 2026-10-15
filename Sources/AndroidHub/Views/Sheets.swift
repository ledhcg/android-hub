import AdbKit
import EmulatorKit
import SwiftUI

/// Pair a phone wirelessly (Android 11+ code pairing) or switch a USB phone to Wi-Fi debugging.
struct PairDeviceSheet: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairingAddress = ""
    @State private var code = ""
    @State private var connectAddress = ""
    @State private var services: [MdnsService] = []
    @State private var log = ""
    @State private var busy = false
    @State private var usbSerial = ""

    private var usbDevices: [Device] { store.devices.filter { $0.connection == .usb && $0.isReady } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thêm thiết bị qua Wi-Fi").font(.title2.weight(.semibold))
            GroupBox("Android 11 trở lên — ghép bằng mã") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trên điện thoại: Cài đặt → Tuỳ chọn nhà phát triển → Gỡ lỗi không dây → “Ghép nối thiết bị bằng mã ghép nối”.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("IP:cổng ghép nối", text: $pairingAddress).textFieldStyle(.roundedBorder)
                        TextField("Mã 6 số", text: $code).textFieldStyle(.roundedBorder).frame(width: 90)
                        Button("Ghép đôi") { run { try store.client.pair(address: pairingAddress, code: code) } }.disabled(pairingAddress.isEmpty || code.isEmpty || busy)
                    }
                    HStack {
                        TextField("IP:cổng kết nối (hiện ở màn hình Gỡ lỗi không dây)", text: $connectAddress).textFieldStyle(.roundedBorder)
                        Button("Kết nối") { run { try store.client.connect(address: connectAddress) } }.disabled(connectAddress.isEmpty || busy)
                    }
                    HStack {
                        Button("Tìm tự động (mDNS)") { discover() }
                        ForEach(services, id: \.name) { service in
                            Button("\(service.kind == .pairing ? "Ghép" : "Kết nối") \(service.address)") {
                                if service.kind == .pairing { pairingAddress = service.address } else { connectAddress = service.address }
                            }.buttonStyle(.link)
                        }
                    }
                }.padding(6)
            }
            GroupBox("Android 10 trở xuống — qua USB") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cắm cáp USB, chuyển adbd sang TCP/IP rồi rút cáp. Máy và Mac phải cùng mạng Wi-Fi.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker("Thiết bị USB", selection: $usbSerial) {
                            Text("Chọn…").tag("")
                            ForEach(usbDevices) { Text($0.displayName).tag($0.serial) }
                        }
                        Button("Bật TCP/IP & kết nối") { enableTCPIP() }.disabled(usbSerial.isEmpty || busy)
                    }
                }.padding(6)
            }
            if !log.isEmpty { Text(log).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 560)
    }

    private func run(_ work: @escaping @Sendable () throws -> String) {
        busy = true
        Task {
            defer { busy = false }
            do { log = try await offMain(work) } catch { log = error.userMessage }
        }
    }

    private func discover() {
        let client = store.client
        Task {
            do {
                services = try await offMain { try client.discoverWirelessServices() }
                log = services.isEmpty ? "Không thấy dịch vụ nào. Bật “Gỡ lỗi không dây” trên điện thoại và để màn hình ghép đôi mở." : ""
            } catch { log = error.userMessage }
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
                    guard let ip = try client.wifiAddress(serial: serial) else { return reply + "\nKhông đọc được địa chỉ Wi-Fi của thiết bị." }
                    return reply + "\n" + (try client.connect(address: "\(ip):5555"))
                }
                log = result
            } catch { log = error.userMessage }
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
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emulator mới").font(.title2.weight(.semibold))
            Form {
                TextField("Tên", text: $name)
                Picker("Thiết bị", selection: $hardware) { ForEach(hardwareList, id: \.self) { Text($0).tag($0) } }
                Picker("System image", selection: $image) {
                    ForEach(images) { Text($0.packageId.replacingOccurrences(of: "system-images;", with: "")).tag($0.packageId) }
                }
            }
            if images.isEmpty {
                Text("Chưa có system image nào. Tải một image bằng package id bên dưới (cần chấp nhận license trước: `sdkmanager --licenses`).").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("system-images;android-35;google_apis;arm64-v8a", text: $downloadId).textFieldStyle(.roundedBorder)
                Button("Tải image") { download() }.disabled(downloadId.isEmpty || busy)
            }
            if !log.isEmpty { ScrollView { Text(log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Tạo") { create() }.buttonStyle(.borderedProminent).disabled(name.isEmpty || image.isEmpty || busy)
            }
        }
        .padding(20).frame(width: 520)
        .task { await load() }
    }

    private func load() async {
        guard let manager = store.avdManager else { log = EmulatorError.sdkNotFound.description; return }
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
            } catch { log = error.userMessage }
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
                log = "Đã cài \(id)"
            } catch { log = error.userMessage }
        }
    }
}

struct AVDDetailView: View {
    let avd: AVD
    @EnvironmentObject var store: DeviceStore
    @State private var headless = false
    @State private var coldBoot = false
    @State private var wipe = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(avd.displayName).font(.title2.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("Thiết bị", avd.deviceDefinition)
                row("API", avd.apiTarget)
                row("ABI", avd.abi)
                row("Màn hình", avd.width.flatMap { w in avd.height.map { "\(w)×\($0) @\(avd.density ?? 0)dpi" } })
                row("RAM", avd.ramMegabytes.map { "\($0) MB" })
                row("Play Store", avd.hasPlayStore ? "Có" : "Không")
                row("System image", avd.systemImage)
            }
            .font(.callout)
            HStack {
                Toggle("Không cửa sổ", isOn: $headless)
                Toggle("Cold boot", isOn: $coldBoot)
                Toggle("Xoá dữ liệu", isOn: $wipe)
            }
            if store.startingAVDs.contains(avd.name) {
                ProgressView("Đang khởi động…")
            } else {
                Button("Khởi động") { store.start(avd: avd, options: EmulatorLaunchOptions(headless: headless, coldBoot: coldBoot, wipeData: wipe)) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value { GridRow { Text(label).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    }
}
