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

/// The canvas: the live screen inside a bezel, with side buttons, navigation row and capture tools.
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
        .canvasBackground()
        .overlay(alignment: .top) { toast }
        .onChange(of: device.serial) { zoom = .fit }
        .task(id: device.serial) { await loadDensity() }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        switch device.state {
        case .unauthorized:
            StatusMessage(
                symbol: "lock.shield", title: "USB Debugging Not Authorized",
                message: "Unlock the phone and tap Allow in the \"Allow USB debugging?\" dialog. If you don't see it, go to Developer options → Revoke USB debugging authorizations, then reconnect the cable.")
        case .offline:
            StatusMessage(symbol: "bolt.slash", title: "Device Is Offline", message: "Try unplugging and reconnecting the cable, or run `adb reconnect`.")
        case .noPermissions:
            StatusMessage(symbol: "hand.raised", title: "No Permission to Access Device", message: "Check the USB cable/port and system permissions.")
        case .device:
            switch controller.state {
            case .idle: idle
            case .starting: starting
            case .failed(let message): failed(message)
            case .running: screen
            }
        default:
            StatusMessage(symbol: "questionmark.circle", title: "State: \(device.state.rawValue)", message: "The device isn't ready.")
        }
    }

    private var idle: some View {
        StatusMessage(
            symbol: "iphone.gen3", title: deviceName,
            message: "Unlock the device, then click View Screen to view and control it.", tint: Brand.green
        ) {
            Button("View Screen") { controller.start() }
                .prominentActionStyle().controlSize(.large).keyboardShortcut(.defaultAction)
            if device.usbVendorName?.lowercased().contains("xiaomi") == true {
                Text("Xiaomi devices: also enable “USB debugging (Security settings)” in Developer options to control the device with the mouse and keyboard.")
                    .font(TypeRole.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
    }

    private var starting: some View {
        VStack(spacing: Space.md) {
            ProgressView().controlSize(.large).padding(.bottom, Space.xs)
            Text("Starting scrcpy-server on the device…").font(TypeRole.title).foregroundStyle(.primary)
            Text("The first start on some devices can take a few dozen seconds.")
                .font(TypeRole.secondary).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Cancel") { controller.stop() }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        StatusMessage(
            symbol: "exclamationmark.triangle", title: "Can't View Screen",
            message: "The screen couldn't be started. Check that the device is unlocked, then try again.", tint: .orange
        ) {
            ScrollView { Text(message).font(TypeRole.mono).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxWidth: 520, maxHeight: 160).wellStyle()
            Button("Try Again") { controller.start() }.prominentActionStyle()
        }
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
        .padding(isCompact ? Space.xs + 2 : Space.lg)
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
                Text(controller.markedText).font(TypeRole.title).padding(.horizontal, Space.md).padding(.vertical, Space.xs)
                    .glassSurface(in: Capsule()).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, bezel + 40)
            }
        }
    }

    /// Power and volume buttons sit on the right edge like a real phone; each is clickable.
    private func sideButtons(size: CGSize) -> some View {
        let height = size.height
        return ZStack(alignment: .topTrailing) {
            sideButton(.volumeUp, "Volume Up", y: height * 0.17)
            sideButton(.volumeDown, "Volume Down", y: height * 0.25)
            sideButton(.power, "Power / Lock Screen", y: height * 0.36, length: height * 0.09)
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
        HStack(spacing: Space.xs) {
            tool("chevron.backward", "Back (right-click)") { controller.press(.back) }
            tool("circle", "Home (middle-click)") { controller.press(.home) }
            tool("square.on.square", "Recents") { controller.press(.recents) }
            Divider().frame(height: 18)
            tool("camera", "Take Screenshot (⌘S)") { controller.screenshot(deviceName: deviceName) }
            if controller.isRecording {
                tool("stop.circle.fill", "Stop Recording", tint: .red) { controller.stopRecording() }
            } else {
                tool("record.circle", "Record Screen (⇧⌘R)") { controller.startRecording(deviceName: deviceName) }
            }
            tool("rotate.left", "Rotate Device") { controller.rotateDevice() }
            tool("bell", "Notifications") { controller.press(.notifications) }
            tool("switch.2", "Quick Settings") { controller.press(.quickSettings) }
            if !isCompact {
                Divider().frame(height: 18)
                tool("minus.magnifyingglass", "Zoom Out") { stepZoom(-1) }
                tool("plus.magnifyingglass", "Zoom In") { stepZoom(1) }
                tool("arrow.up.left.and.down.right.magnifyingglass", "Fit to Window") { zoom = .fit }
                tool("ruler", "Actual Size (≈)") { zoom = .physical }
                tool("rectangle.dashed", "Resize Mode") { showResize.toggle() }
                    .popover(isPresented: $showResize) { ResizeModeView(device: device).environmentObject(store) }
                tool(showBezels ? "iphone.gen3" : "iphone.gen3.slash", showBezels ? "Hide Bezels" : "Show Bezels") { showBezels.toggle() }
            }
            Spacer()
            if let size = controller.frameSize {
                Text("\(size.width)×\(size.height)").font(TypeRole.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            tool("stop.fill", "Stop Viewing Screen") { controller.stop() }
        }
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .glassSurface(in: Capsule())
        .padding(.horizontal, Space.md).padding(.bottom, Space.sm)
    }

    private func tool(_ symbol: String, _ help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).symbolRenderingMode(.hierarchical).frame(width: Space.xl, height: Space.xl) }
            .buttonStyle(.borderless).foregroundStyle(tint ?? .primary).help(help).accessibilityLabel(help)
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
            Text(text).font(TypeRole.secondary).padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .glassSurface(in: Capsule()).padding(.top, Space.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Resize mode: try arbitrary screen sizes without owning every device (`wm size`).
struct ResizeModeView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @State private var width = ""
    @State private var height = ""
    @State private var error: String?

    private let presets: [(String, Int, Int)] = [
        ("Small 720×1280", 720, 1280), ("1080×1920", 1080, 1920), ("1080×2400", 1080, 2400), ("1440×3200", 1440, 3200),
        ("Tablet 1600×2560", 1600, 2560), ("Foldable 1768×2208", 1768, 2208),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Resize Screen").font(TypeRole.section)
            HStack {
                TextField("Width", text: $width).frame(width: 70)
                Text("×")
                TextField("Height", text: $height).frame(width: 70)
                Button("Apply") { apply(.displaySize(width: Int(width) ?? 0, height: Int(height) ?? 0)) }
                    .disabled(Int(width) == nil || Int(height) == nil)
            }
            ForEach(presets, id: \.0) { preset in
                Button(preset.0) { width = "\(preset.1)"; height = "\(preset.2)"; apply(.displaySize(width: preset.1, height: preset.2)) }
                    .buttonStyle(.link)
            }
            Divider()
            Button("Restore Original Size") { apply(.resetDisplaySize); apply(.resetDisplayDensity) }
            if let error { Text(error).font(TypeRole.caption).foregroundStyle(.red) }
        }
        .padding(Space.lg).frame(width: 280)
    }

    private func apply(_ change: SettingChange) {
        let (client, serial) = (store.client, device.serial)
        Task {
            do { try await offMain { try client.apply(change, serial: serial) }; error = nil } catch { self.error = error.userMessage }
        }
    }
}
