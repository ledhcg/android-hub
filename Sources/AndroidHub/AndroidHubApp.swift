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

        WindowGroup("Device", for: String.self) { $serial in
            if let serial { CompactDeviceWindow(serial: serial).environmentObject(store).frame(minWidth: 220, minHeight: 360) }
        }
        .defaultSize(width: 300, height: 640)
        // A compact window starts mirroring as soon as it appears; never reopen one (and so a device's screen) on launch.
        .restorationBehavior(.disabled)
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

/// Menu commands that act on the device of the FRONT window (Controls / Device menus).
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
            do { try await offMain { try client.apply(change, serial: serial) } } catch { store.report(error, title: "Couldn't Change Setting") }
        }
    }

    var body: some Commands {
        CommandMenu("Controls") {
            Button("View Screen") { controller?.start() }.keyboardShortcut("r", modifiers: [.command]).disabled(controller?.isRunning ?? true)
            Button("Stop Viewing Screen") { controller?.stop() }.disabled(!(controller?.isRunning ?? false))
            Divider()
            Button("Home") { controller?.press(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Back") { controller?.press(.back) }.keyboardShortcut("[", modifiers: [.command])
            Button("Recents") { controller?.press(.recents) }.keyboardShortcut("]", modifiers: [.command])
            Button("Lock / Power") { controller?.press(.power) }.keyboardShortcut("l", modifiers: [.command])
            Divider()
            Button("Rotate Device") { controller?.rotateDevice() }.keyboardShortcut(.rightArrow, modifiers: [.command])
            Button("Notifications") { controller?.press(.notifications) }
            Button("Quick Settings") { controller?.press(.quickSettings) }
            Divider()
            Button("Volume Up") { controller?.press(.volumeUp) }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            Button("Volume Down") { controller?.press(.volumeDown) }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Divider()
            Button("Take Screenshot") { controller?.screenshot(deviceName: name) }.keyboardShortcut("s", modifiers: [.command])
            Button((controller?.isRecording ?? false) ? "Stop Recording" : "Record Screen") {
                if controller?.isRecording ?? false { controller?.stopRecording() } else { controller?.startRecording(deviceName: name) }
            }.keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandMenu("Device") {
            Menu("Appearance") {
                Button("Light") { apply(.appearance(.light)) }
                Button("Dark") { apply(.appearance(.dark)) }
                Button("Automatic") { apply(.appearance(.auto)) }
            }
            Menu("Orientation") {
                Button("Portrait") { apply(.rotation(.portrait)) }
                Button("Landscape Left") { apply(.rotation(.landscapeLeft)) }
                Button("Portrait Upside Down") { apply(.rotation(.portraitUpsideDown)) }
                Button("Landscape Right") { apply(.rotation(.landscapeRight)) }
                Divider()
                Button("Auto-Rotate") { apply(.autoRotate(true)) }
            }
            Menu("Animation") {
                Button("Slow Animations (10×)") { apply(.animationScale(10)) }
                Button("Normal Animations (1×)") { apply(.animationScale(1)) }
            }
            Divider()
            Button("Show Touches") { apply(.showTouches(true)) }
            Button("Hide Touches") { apply(.showTouches(false)) }
        }
    }
}
