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
                .canvasBackground()
                .inspector(isPresented: Binding(get: { showInspector && store.selectedDevice != nil }, set: { showInspector = $0 })) {
                    if let device = store.selectedDevice {
                        InspectorView(device: device).inspectorColumnWidth(min: 320, ideal: 380, max: 560)
                    }
                }
        }
        .navigationTitle(title)
        // Let the canvas surface run under the toolbar so title bar and content share one tone (no seam).
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Pair Device over Wi-Fi…") { showPair = true }
                    Button("New Emulator…") { showNewEmulator = true }
                } label: { Label("Add Device", systemImage: "plus") }
                .help("Add Device")
            }
            ToolbarItemGroup {
                if let device = store.selectedDevice, device.isReady {
                    Button { openWindow(value: device.serial) } label: { Label("Open Compact Window", systemImage: "rectangle.on.rectangle") }
                        .help("Open Compact Window")
                }
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .help("Show/Hide Inspector").disabled(store.selectedDevice == nil)
            }
        }
        .sheet(isPresented: $showPair) { PairDeviceSheet().environmentObject(store) }
        .sheet(isPresented: $showNewEmulator) { NewEmulatorSheet().environmentObject(store) }
        .alert(
            store.alert?.title ?? "", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0.message) }
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
            StatusMessage(symbol: "iphone.gen3", title: "Select a Device", message: "Select a device in the sidebar to view its screen and manage it.")
        }
    }
}

/// The small standalone window opened for a running device.
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
            StatusMessage(symbol: "bolt.slash", title: "Device Disconnected", message: serial).canvasBackground()
        }
    }
}
