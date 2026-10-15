import AdbKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showInspector") private var showInspector = true
    @State private var showPair = false
    @State private var showNewEmulator = false

    var body: some View {
        NavigationSplitView {
            SidebarView().navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detail
                .inspector(isPresented: Binding(get: { showInspector && store.selectedDevice != nil }, set: { showInspector = $0 })) {
                    if let device = store.selectedDevice {
                        InspectorView(device: device).inspectorColumnWidth(min: 320, ideal: 380, max: 560)
                    }
                }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Ghép đôi thiết bị qua Wi-Fi…") { showPair = true }
                    Button("Emulator mới…") { showNewEmulator = true }
                } label: { Image(systemName: "plus") }
                .help("Thêm thiết bị")
                if let device = store.selectedDevice, device.isReady {
                    Button { openWindow(value: device.serial) } label: { Image(systemName: "rectangle.on.rectangle") }
                        .help("Mở cửa sổ nhỏ gọn")
                }
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                    .help("Hiện/ẩn Inspector").disabled(store.selectedDevice == nil)
            }
        }
        .sheet(isPresented: $showPair) { PairDeviceSheet().environmentObject(store) }
        .sheet(isPresented: $showNewEmulator) { NewEmulatorSheet().environmentObject(store) }
        .alert(item: $store.alert) { Alert(title: Text($0.title), message: Text($0.message)) }
        .frame(minWidth: 820, minHeight: 560)
        .focusedSceneValue(\.activeSerial, store.selectedDevice?.serial)
    }

    private var title: String {
        if let device = store.selectedDevice { return store.name(of: .device(device)) }
        if let avd = store.selectedAVD { return avd.displayName }
        return "Android Hub"
    }

    @ViewBuilder private var detail: some View {
        if let device = store.selectedDevice {
            DeviceCanvasView(device: device, controller: store.controller(for: device.serial))
        } else if let avd = store.selectedAVD {
            AVDDetailView(avd: avd)
        } else {
            ContentUnavailableView("Chọn một thiết bị", systemImage: "iphone.gen3", description: Text("Chọn thiết bị ở thanh bên để xem màn hình và quản lý."))
        }
    }
}

/// The small standalone window Device Hub opens for a running device.
struct CompactDeviceWindow: View {
    let serial: String
    @EnvironmentObject var store: DeviceStore

    var body: some View {
        if let device = store.devices.first(where: { $0.serial == serial }) {
            DeviceCanvasView(device: device, controller: store.controller(for: serial), isCompact: true)
                .navigationTitle(store.name(of: .device(device)))
                .focusedSceneValue(\.activeSerial, serial)
                .task { if device.isReady, !store.controller(for: serial).isRunning { store.controller(for: serial).start() } }
        } else {
            StatusMessage(symbol: "bolt.slash", title: "Thiết bị đã ngắt kết nối", message: serial)
        }
    }
}
