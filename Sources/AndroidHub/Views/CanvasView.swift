import AdbKit
import AppKit
import ScrcpyKit
import SwiftUI

/// One canvas per SwiftUI host; all canvases of a device share its scrcpy session through `MirrorController`.
struct MirrorRepresentable: NSViewRepresentable {
    let controller: MirrorController

    func makeNSView(context: Context) -> MirrorNSView { controller.makeView() }
    func updateNSView(_ nsView: MirrorNSView, context: Context) {}
    static func dismantleNSView(_ nsView: MirrorNSView, coordinator: ()) {
        // The view deregisters itself from the hub lazily (weak reference), nothing else to release.
    }
}

enum CanvasZoom: Equatable {
    case fit
    case scale(Double)
    /// ≈ the real size of the device's screen (density-based).
    case physical
}

/// The Device Hub "canvas": the live screen inside a bezel, with side buttons, navigation row and capture tools.
struct DeviceCanvasView: View {
    let device: Device
    @ObservedObject var controller: MirrorController
    var isCompact = false

    @EnvironmentObject var store: DeviceStore
    @AppStorage("showBezels") private var showBezels = true
    @State private var zoom: CanvasZoom = .fit
    @State private var showResize = false
    @State private var density: Int?

    private var deviceName: String { store.name(of: .device(device)) }

    var body: some View {
        VStack(spacing: 0) {
            content
            if controller.state == .running { toolbar }
        }
        .overlay(alignment: .top) { toast }
        .onChange(of: device.serial) { _ in zoom = .fit }
        .task(id: device.serial) { await loadDensity() }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        switch device.state {
        case .unauthorized:
            StatusMessage(
                symbol: "lock.shield", title: "Chưa cấp quyền USB debugging",
                message: "Mở khoá điện thoại và bấm Allow ở hộp thoại \"Allow USB debugging?\". Nếu không thấy, vào Tuỳ chọn nhà phát triển → Thu hồi quyền gỡ lỗi USB rồi cắm lại cáp.")
        case .offline:
            StatusMessage(symbol: "bolt.slash", title: "Thiết bị đang offline", message: "Thử rút cáp cắm lại, hoặc chạy `adb reconnect`.")
        case .noPermissions:
            StatusMessage(symbol: "hand.raised", title: "Không có quyền truy cập thiết bị", message: "Kiểm tra cáp/cổng USB và quyền của hệ thống.")
        case .device:
            switch controller.state {
            case .idle: idle
            case .starting: starting
            case .failed(let message): failed(message)
            case .running: screen
            }
        default:
            StatusMessage(symbol: "questionmark.circle", title: "Trạng thái: \(device.state.rawValue)", message: "Thiết bị chưa sẵn sàng.")
        }
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(deviceName).font(.title2.weight(.semibold))
            Text("Mở khoá thiết bị rồi bấm View Screen để xem và điều khiển.").foregroundStyle(.secondary)
            Button("View Screen") { controller.start() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            if device.usbVendorName?.lowercased().contains("xiaomi") == true {
                Text("Máy Xiaomi: bật thêm “USB debugging (Security settings)” trong Tuỳ chọn nhà phát triển để điều khiển bằng chuột/bàn phím.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var starting: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Đang khởi động scrcpy-server trên thiết bị…")
            Text("Lần đầu trên một số máy có thể mất vài chục giây.").font(.caption).foregroundStyle(.secondary)
            Button("Huỷ") { controller.stop() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text("Không xem được màn hình").font(.title3.weight(.semibold))
            ScrollView { Text(message).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxWidth: 520, maxHeight: 160).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Button("Thử lại") { controller.start() }.buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Live screen

    private var screen: some View {
        GeometryReader { geometry in
            let size = deviceSize(in: geometry.size)
            ZStack {
                Color.clear
                bezelledScreen(size: size).frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .padding(isCompact ? 6 : 16)
    }

    private func bezelledScreen(size: CGSize) -> some View {
        let bezel: CGFloat = showBezels ? max(8, size.width * 0.035) : 0
        let radius = showBezels ? size.width * 0.12 : 6
        return ZStack {
            if showBezels {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black)
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.gray.opacity(0.5), lineWidth: 1.5)
                sideButtons(size: size)
            }
            MirrorRepresentable(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: max(radius - bezel, 4), style: .continuous))
                .padding(bezel)
            if !controller.markedText.isEmpty {
                Text(controller.markedText).font(.title3).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.ultraThickMaterial, in: Capsule()).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, bezel + 40)
            }
        }
    }

    /// Power and volume buttons sit on the right edge like a real phone; each is clickable.
    private func sideButtons(size: CGSize) -> some View {
        let height = size.height
        return ZStack(alignment: .topTrailing) {
            sideButton(.volumeUp, "Tăng âm lượng", y: height * 0.17)
            sideButton(.volumeDown, "Giảm âm lượng", y: height * 0.25)
            sideButton(.power, "Nguồn / Khoá màn hình", y: height * 0.36, length: height * 0.09)
        }
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
    }

    private func sideButton(_ button: DeviceButton, _ help: String, y: CGFloat, length: CGFloat = 36) -> some View {
        Button { controller.press(button) } label: {
            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.65)).frame(width: 5, height: length)
        }
        .buttonStyle(.plain).help(help).offset(x: 4, y: y)
    }

    private func deviceSize(in available: CGSize) -> CGSize {
        let frame = controller.frameSize ?? FrameSize(width: device.model == nil ? 1080 : 1080, height: 2400)
        let aspect = CGFloat(frame.width) / CGFloat(max(frame.height, 1))
        let chrome: CGFloat = showBezels ? 1.07 : 1
        let fit: CGSize = {
            var height = available.height
            var width = height * aspect * chrome
            if width > available.width { width = available.width; height = width / (aspect * chrome) }
            return CGSize(width: max(width, 40), height: max(height, 40))
        }()
        switch zoom {
        case .fit: return fit
        case .scale(let factor):
            let scaled = CGSize(width: CGFloat(frame.width) * chrome * factor / 2, height: CGFloat(frame.height) * chrome * factor / 2)
            return scaled
        case .physical:
            // density = dpi; points per inch on a Mac ≈ 110.
            let dpi = CGFloat(density ?? 420)
            let ppi: CGFloat = 110
            return CGSize(width: CGFloat(frame.width) / dpi * ppi * chrome, height: CGFloat(frame.height) / dpi * ppi * chrome)
        }
    }

    private func loadDensity() async {
        let client = store.client
        let serial = device.serial
        if let info = try? await offMain({ try client.deviceInfo(serial: serial) }) {
            density = info.overrideDensity ?? info.physicalDensity
        }
    }

    // MARK: Toolbar under the device

    private var toolbar: some View {
        HStack(spacing: 4) {
            tool("chevron.backward", "Back (chuột phải)") { controller.press(.back) }
            tool("circle", "Home (chuột giữa)") { controller.press(.home) }
            tool("square.on.square", "Recents") { controller.press(.recents) }
            Divider().frame(height: 18)
            tool("camera", "Chụp màn hình (⌘S)") { controller.screenshot(deviceName: deviceName) }
            if controller.isRecording {
                tool("stop.circle.fill", "Dừng quay", tint: .red) { controller.stopRecording() }
            } else {
                tool("record.circle", "Quay màn hình (⇧⌘R)") { controller.startRecording(deviceName: deviceName) }
            }
            tool("rotate.left", "Xoay thiết bị") { controller.rotateDevice() }
            tool("bell", "Thông báo") { controller.press(.notifications) }
            tool("switch.2", "Cài đặt nhanh") { controller.press(.quickSettings) }
            if !isCompact {
                Divider().frame(height: 18)
                tool("minus.magnifyingglass", "Thu nhỏ") { stepZoom(-1) }
                tool("plus.magnifyingglass", "Phóng to") { stepZoom(1) }
                tool("arrow.up.left.and.down.right.magnifyingglass", "Vừa khung") { zoom = .fit }
                tool("ruler", "Kích thước thật (≈)") { zoom = .physical }
                tool("rectangle.dashed", "Chế độ đổi kích thước") { showResize.toggle() }
                    .popover(isPresented: $showResize) { ResizeModeView(device: device).environmentObject(store) }
                tool(showBezels ? "iphone.gen3" : "iphone.gen3.slash", showBezels ? "Ẩn viền" : "Hiện viền") { showBezels.toggle() }
            }
            Spacer()
            if let size = controller.frameSize {
                Text("\(size.width)×\(size.height)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            tool("stop.fill", "Dừng xem màn hình") { controller.stop() }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
    }

    private func tool(_ symbol: String, _ help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 20) }
            .buttonStyle(.borderless).foregroundStyle(tint ?? .primary).help(help)
    }

    private func stepZoom(_ direction: Int) {
        let current: Double
        switch zoom {
        case .scale(let value): current = value
        default: current = 0.5
        }
        zoom = .scale(min(max(current + Double(direction) * 0.1, 0.2), 2.0))
    }

    @ViewBuilder private var toast: some View {
        if let text = controller.toast {
            Text(text).font(.callout).padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule()).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct StatusMessage: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Device Hub's "resize mode": try arbitrary screen sizes without owning every device (`wm size`).
struct ResizeModeView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @State private var width = ""
    @State private var height = ""
    @State private var error: String?

    private let presets: [(String, Int, Int)] = [
        ("Nhỏ 720×1280", 720, 1280), ("1080×1920", 1080, 1920), ("1080×2400", 1080, 2400), ("1440×3200", 1440, 3200),
        ("Máy tính bảng 1600×2560", 1600, 2560), ("Gập 1768×2208", 1768, 2208),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Đổi kích thước màn hình").font(.headline)
            HStack {
                TextField("Rộng", text: $width).frame(width: 70)
                Text("×")
                TextField("Cao", text: $height).frame(width: 70)
                Button("Áp dụng") { apply(.displaySize(width: Int(width) ?? 0, height: Int(height) ?? 0)) }
                    .disabled(Int(width) == nil || Int(height) == nil)
            }
            ForEach(presets, id: \.0) { preset in
                Button(preset.0) { width = "\(preset.1)"; height = "\(preset.2)"; apply(.displaySize(width: preset.1, height: preset.2)) }
                    .buttonStyle(.link)
            }
            Divider()
            Button("Khôi phục kích thước gốc") { apply(.resetDisplaySize); apply(.resetDisplayDensity) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding().frame(width: 280)
    }

    private func apply(_ change: SettingChange) {
        let (client, serial) = (store.client, device.serial)
        Task {
            do { try await offMain { try client.apply(change, serial: serial) }; error = nil } catch { self.error = error.userMessage }
        }
    }
}
