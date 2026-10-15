import AdbKit
import AppKit
import SwiftUI

@main
struct AndroidHubApp: App {
    @StateObject private var store = DeviceStore()

    init() {
        // Needed when launched as a bare executable (swift run); harmless inside the .app bundle.
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Android Hub", id: "main") {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { DeviceCommands(store: store) }

        WindowGroup("Thiết bị", for: String.self) { $serial in
            if let serial { CompactDeviceWindow(serial: serial).environmentObject(store).frame(minWidth: 220, minHeight: 360) }
        }
        .defaultSize(width: 300, height: 640)
    }
}

/// The device shown by the window that currently has focus (main window → its selection, compact window → its own).
struct ActiveSerialKey: FocusedValueKey { typealias Value = String }

extension FocusedValues {
    var activeSerial: String? {
        get { self[ActiveSerialKey.self] }
        set { self[ActiveSerialKey.self] = newValue }
    }
}

/// Menu commands that act on the device of the FRONT window (Controls / Device menus, like Device Hub).
struct DeviceCommands: Commands {
    @ObservedObject var store: DeviceStore
    @FocusedValue(\.activeSerial) private var activeSerial: String?

    private var device: Device? { activeSerial.flatMap { serial in store.devices.first { $0.serial == serial } } }
    private var controller: MirrorController? { device.map { store.controller(for: $0.serial) } }
    private var name: String { device.map { store.name(of: .device($0)) } ?? "Android" }

    private func apply(_ change: SettingChange) {
        guard let device else { return }
        let (client, serial) = (store.client, device.serial)
        Task {
            do { try await offMain { try client.apply(change, serial: serial) } } catch { store.report(error, title: "Không đổi được cài đặt") }
        }
    }

    var body: some Commands {
        CommandMenu("Điều khiển") {
            Button("Xem màn hình") { controller?.start() }.keyboardShortcut("r", modifiers: [.command]).disabled(controller?.isRunning ?? true)
            Button("Dừng xem màn hình") { controller?.stop() }.disabled(!(controller?.isRunning ?? false))
            Divider()
            Button("Home") { controller?.press(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Back") { controller?.press(.back) }.keyboardShortcut("[", modifiers: [.command])
            Button("Recents") { controller?.press(.recents) }.keyboardShortcut("]", modifiers: [.command])
            Button("Khoá / Nguồn") { controller?.press(.power) }.keyboardShortcut("l", modifiers: [.command])
            Divider()
            Button("Xoay thiết bị") { controller?.rotateDevice() }.keyboardShortcut(.rightArrow, modifiers: [.command])
            Button("Thông báo") { controller?.press(.notifications) }
            Button("Cài đặt nhanh") { controller?.press(.quickSettings) }
            Divider()
            Button("Tăng âm lượng") { controller?.press(.volumeUp) }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            Button("Giảm âm lượng") { controller?.press(.volumeDown) }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Divider()
            Button("Chụp màn hình") { controller?.screenshot(deviceName: name) }.keyboardShortcut("s", modifiers: [.command])
            Button((controller?.isRecording ?? false) ? "Dừng quay màn hình" : "Quay màn hình") {
                if controller?.isRecording ?? false { controller?.stopRecording() } else { controller?.startRecording(deviceName: name) }
            }.keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandMenu("Thiết bị") {
            Menu("Giao diện") {
                Button("Sáng") { apply(.appearance(.light)) }
                Button("Tối") { apply(.appearance(.dark)) }
                Button("Tự động") { apply(.appearance(.auto)) }
            }
            Menu("Hướng") {
                Button("Dọc") { apply(.rotation(.portrait)) }
                Button("Ngang trái") { apply(.rotation(.landscapeLeft)) }
                Button("Dọc ngược") { apply(.rotation(.portraitUpsideDown)) }
                Button("Ngang phải") { apply(.rotation(.landscapeRight)) }
                Divider()
                Button("Tự xoay") { apply(.autoRotate(true)) }
            }
            Menu("Animation") {
                Button("Làm chậm (10×)") { apply(.animationScale(10)) }
                Button("Bình thường (1×)") { apply(.animationScale(1)) }
            }
            Divider()
            Button("Hiện điểm chạm") { apply(.showTouches(true)) }
            Button("Ẩn điểm chạm") { apply(.showTouches(false)) }
        }
    }
}
