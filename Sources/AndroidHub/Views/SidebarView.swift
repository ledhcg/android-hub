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
            controls
            if let error = store.adbError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(8)
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
                    Section("Thiết bị thật") { ForEach(physical) { row($0).tag($0.id) } }
                }
                if !emulators.isEmpty {
                    Section("Emulator") { ForEach(emulators) { row($0).tag($0.id) } }
                }
                if items.isEmpty {
                    ContentUnavailableView(
                        "Chưa có thiết bị", systemImage: "cable.connector",
                        description: Text("Cắm điện thoại bằng cáp USB và bật USB debugging, hoặc thêm thiết bị qua nút +."))
                }
            }
            .listStyle(.sidebar)
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Tìm thiết bị")
        .confirmationDialog(
            pendingTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible
        ) {
            switch pending {
            case .wipe(let avd): Button("Xoá dữ liệu", role: .destructive) { store.wipe(avd: avd) }
            case .delete(let avd): Button("Xoá AVD", role: .destructive) { store.delete(avd: avd) }
            case nil: EmptyView()
            }
        } message: {
            Text(pendingMessage)
        }
    }

    private var controls: some View {
        HStack {
            Picker("Lọc", selection: $store.filter) { ForEach(SidebarFilter.allCases) { Text($0.rawValue).tag($0) } }
                .labelsHidden().pickerStyle(.menu)
            Menu {
                Picker("Sắp xếp", selection: $store.sort) { ForEach(SidebarSort.allCases) { Text($0.rawValue).tag($0) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }

    @ViewBuilder private func row(_ item: SidebarItem) -> some View {
        switch item {
        case .device(let device):
            HStack {
                Image(systemName: icon(for: device)).foregroundStyle(device.isReady ? .primary : .secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.name(of: item)).lineLimit(1)
                    Text(subtitle(for: device)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if store.controller(for: device.serial).isRunning { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green).help("Đang xem màn hình") }
            }
            .contextMenu {
                Button("Mở cửa sổ nhỏ gọn") { openWindow(value: device.serial) }.disabled(!device.isReady)
                if device.connection == .emulator {
                    Button("Tắt emulator") { store.stopEmulator(serial: device.serial) }
                }
                if device.connection == .network {
                    Button("Ngắt kết nối") { store.disconnect(device: device) }
                }
                Button("Chép serial") { copy(device.serial) }
            }
        case .avd(let avd):
            HStack {
                Image(systemName: "desktopcomputer").foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(avd.displayName).lineLimit(1)
                    Text(store.startingAVDs.contains(avd.name) ? "Đang khởi động…" : "AVD • \(avd.apiTarget ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.startingAVDs.contains(avd.name) { ProgressView().controlSize(.small) }
            }
            .contextMenu {
                Button("Khởi động") { store.start(avd: avd) }
                Button("Khởi động (cold boot)") { store.start(avd: avd, options: EmulatorLaunchOptions(coldBoot: true)) }
                Button("Khởi động không cửa sổ") { store.start(avd: avd, options: EmulatorLaunchOptions(headless: true)) }
                Divider()
                Button("Xoá dữ liệu…") { pending = .wipe(avd) }
                Button("Xoá AVD…", role: .destructive) { pending = .delete(avd) }
            }
        }
    }

    private var pendingTitle: String {
        switch pending {
        case .wipe(let avd): "Xoá dữ liệu của \(avd.displayName)?"
        case .delete(let avd): "Xoá \(avd.displayName)?"
        case nil: ""
        }
    }

    private var pendingMessage: String {
        switch pending {
        case .wipe: "Mọi ứng dụng và dữ liệu người dùng trên AVD này sẽ bị mất. Cần tắt emulator trước."
        case .delete: "AVD sẽ bị xoá khỏi ổ đĩa và không thể khôi phục."
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
        case .unauthorized: state = "Chưa cấp quyền"
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
