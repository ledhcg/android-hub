import AdbKit
import EmulatorKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.openWindow) private var openWindow
    @State private var pending: PendingAction?

    /// Destructive actions always ask first.
    private enum PendingAction: Identifiable {
        case wipe(AVD)
        case delete(AVD)
        var id: String {
            switch self {
            case .wipe(let avd): "wipe-\(avd.name)"
            case .delete(let avd): "delete-\(avd.name)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.adbError {
                Label(error, systemImage: "exclamationmark.triangle").font(TypeRole.caption).foregroundStyle(.orange).padding(Space.sm)
            }
            List(selection: $store.selection) {
                let items = store.items()
                let physical = items.filter { if case .device(let d) = $0 { d.connection != .emulator } else { false } }
                let emulators = items.filter {
                    switch $0 {
                    case .device(let d): d.connection == .emulator
                    case .avd: true
                    }
                }
                if !physical.isEmpty {
                    Section("Physical Devices") { ForEach(physical) { row($0).tag($0.id) } }
                }
                if !emulators.isEmpty {
                    Section("Emulator") { ForEach(emulators) { row($0).tag($0.id) } }
                }
                if items.isEmpty {
                    StatusMessage(
                        symbol: "cable.connector", title: "No Devices",
                        message: "Connect a phone with a USB cable and turn on USB debugging, or add a device with the + button.")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search Devices")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Show", selection: $store.filter) { ForEach(SidebarFilter.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.inline)
                    Picker("Sort By", selection: $store.sort) { ForEach(SidebarSort.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.inline)
                } label: { Label("Filter and Sort", systemImage: "line.3.horizontal.decrease") }
                .help("Filter and Sort Devices")
            }
        }
        .confirmationDialog(
            pendingTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible
        ) {
            switch pending {
            case .wipe(let avd): Button("Wipe Data", role: .destructive) { store.wipe(avd: avd) }
            case .delete(let avd): Button("Delete AVD", role: .destructive) { store.delete(avd: avd) }
            case nil: EmptyView()
            }
        } message: {
            Text(pendingMessage)
        }
    }

    @ViewBuilder private func row(_ item: SidebarItem) -> some View {
        switch item {
        case .device(let device):
            HStack(spacing: Space.sm) {
                rowIcon(icon(for: device), dimmed: !device.isReady)
                rowText(store.name(of: item), subtitle(for: device))
                Spacer()
                if store.controller(for: device.serial).isRunning { StatusPill(text: "Live", tint: Brand.green).help("Viewing screen") }
            }
            .contextMenu {
                Button("Open Compact Window") { openWindow(value: device.serial) }.disabled(!device.isReady)
                if device.connection == .emulator {
                    Button("Stop Emulator") { store.stopEmulator(serial: device.serial) }
                }
                if device.connection == .network {
                    Button("Disconnect") { store.disconnect(device: device) }
                }
                Button("Copy Serial") { copy(device.serial) }
            }
        case .avd(let avd):
            HStack(spacing: Space.sm) {
                rowIcon("desktopcomputer", dimmed: true)
                rowText(avd.displayName, store.startingAVDs.contains(avd.name) ? "Starting…" : "AVD • \(avd.apiTarget ?? "")")
                Spacer()
                if store.startingAVDs.contains(avd.name) { ProgressView().controlSize(.small) }
            }
            .contextMenu {
                Button("Start") { store.start(avd: avd) }
                Button("Start (Cold Boot)") { store.start(avd: avd, options: EmulatorLaunchOptions(coldBoot: true)) }
                Button("Start Without Window") { store.start(avd: avd, options: EmulatorLaunchOptions(headless: true)) }
                Divider()
                Button("Wipe Data…") { pending = .wipe(avd) }
                Button("Delete AVD…", role: .destructive) { pending = .delete(avd) }
            }
        }
    }

    private func rowIcon(_ symbol: String, dimmed: Bool) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(dimmed ? .secondary : .primary)
            .frame(width: Space.xl)
            .accessibilityHidden(true)
    }

    private func rowText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(TypeRole.body).lineLimit(1)
            Text(subtitle).font(TypeRole.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var pendingTitle: String {
        switch pending {
        case .wipe(let avd): "Wipe data for \(avd.displayName)?"
        case .delete(let avd): "Delete \(avd.displayName)?"
        case nil: ""
        }
    }

    private var pendingMessage: String {
        switch pending {
        case .wipe: "All apps and user data on this AVD will be lost. Stop the emulator first."
        case .delete: "The AVD will be deleted from disk and can't be recovered."
        case nil: ""
        }
    }

    private func icon(for device: Device) -> String {
        switch device.connection {
        case .usb: "iphone.gen3"
        case .network: "wifi"
        case .emulator: "desktopcomputer"
        }
    }

    private func subtitle(for device: Device) -> String {
        let state: String
        switch device.state {
        case .device: state = device.connection == .emulator ? "Emulator" : (device.connection == .network ? "Wi-Fi" : "USB")
        case .unauthorized: state = "Unauthorized"
        case .offline: state = "Offline"
        default: state = device.state.rawValue
        }
        return "\(state) • \(device.serial)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
