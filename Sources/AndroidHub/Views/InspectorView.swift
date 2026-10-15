import AdbKit
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case info = "Info"
    case apps = "Apps"
    case files = "Files"
    case logs = "Logs"
    case diagnostics = "Diagnostics"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .info: "info.circle"
        case .apps: "square.grid.2x2"
        case .files: "folder"
        case .logs: "text.alignleft"
        case .diagnostics: "stethoscope"
        }
    }
}

/// The inspector: one icon bar, one panel at a time, always for the selected device.
struct InspectorView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @AppStorage("inspectorTab") private var tabName = InspectorTab.settings.rawValue

    private var tab: InspectorTab { InspectorTab(rawValue: tabName) ?? .settings }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tabName) {
                ForEach(InspectorTab.allCases) { candidate in
                    Label(candidate.rawValue, systemImage: candidate.symbol).labelStyle(.iconOnly)
                        .help(candidate.rawValue).accessibilityLabel(candidate.rawValue).tag(candidate.rawValue)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            Divider()
            if device.isReady {
                panel.id("\(device.serial)-\(tab.rawValue)")
            } else {
                StatusMessage(symbol: "iphone.slash", title: "Device Not Ready", message: "The inspector works when the device is in the “device” state.")
            }
        }
        .canvasBackground()
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .settings: SettingsPanel(serial: device.serial, client: store.client)
        case .info: InfoPanel(device: device, client: store.client)
        case .apps: AppsPanel(serial: device.serial, client: store.client)
        case .files: FilesPanel(serial: device.serial, client: store.client)
        case .logs: LogsPanel(serial: device.serial, client: store.client)
        case .diagnostics: DiagnosticsPanel(serial: device.serial, client: store.client)
        }
    }
}

struct ErrorBanner: View {
    let message: String?
    var body: some View {
        if let message {
            Label {
                Text(message).font(TypeRole.caption).foregroundStyle(.primary).textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wellStyle()
            .padding(.horizontal, Space.md).padding(.top, Space.sm)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Info

struct InfoPanel: View {
    let device: Device
    @StateObject private var model: InfoModel
    @State private var propertyFilter = ""

    init(device: Device, client: AdbClient) {
        self.device = device
        _model = StateObject(wrappedValue: InfoModel(serial: device.serial, client: client))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                ErrorBanner(message: model.error)
                if let info = model.info {
                    group("Device") {
                        row("Name", device.displayName)
                        row("Manufacturer", info.manufacturer)
                        row("Model", info.model)
                        row("Marketing Name", info.marketName)
                        row("Codename", info.codename)
                        row("Type", info.isEmulator ? "Emulator" : "Physical Device")
                    }
                    group("Operating System") {
                        row("Android", info.androidVersion.map { "\($0) (SDK \(info.sdkInt.map(String.init) ?? "?"))" })
                        row("Security Patch", info.securityPatch)
                        row("Build", info.buildId)
                        row("ABI", info.primaryABI)
                    }
                    group("Identifiers") {
                        row("Serial / ID", info.serial, copyable: true)
                        row("Connection", device.connection.rawValue.uppercased())
                        row("Transport ID", device.transportId.map(String.init))
                        row("USB Path", device.usbPath)
                    }
                    group("Display") {
                        row("Size", size(info.physicalSize))
                        row("Size (override)", size(info.overrideSize))
                        row("Density", info.physicalDensity.map { "\($0) dpi" })
                        row("Density (override)", info.overrideDensity.map { "\($0) dpi" })
                    }
                    if let battery = info.battery {
                        group("Battery") {
                            row("Battery Level", battery.level.map { "\($0)%" })
                            row("Charging", battery.isCharging.map { $0 ? "Yes" : "No" })
                            row("Power Source", battery.poweredBy.isEmpty ? nil : battery.poweredBy.joined(separator: ", "))
                            row("Temperature", battery.temperatureCelsius.map { String(format: "%.1f °C", $0) })
                        }
                    }
                } else if model.isLoading {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading device info…").font(TypeRole.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(Space.lg)
                } else if model.error != nil {
                    StatusMessage(symbol: "exclamationmark.triangle", title: "Couldn’t Load Device Info", message: "Check that the device is connected and authorized, then reopen this panel.", tint: .orange)
                        .frame(height: 220)
                }
                DisclosureGroup("All System Properties (getprop)", isExpanded: $model.showsProperties) {
                    TextField("Filter", text: $propertyFilter).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Filter properties")
                    let keys = model.properties.keys.sorted().filter { propertyFilter.isEmpty || $0.localizedCaseInsensitiveContains(propertyFilter) || (model.properties[$0] ?? "").localizedCaseInsensitiveContains(propertyFilter) }
                    ForEach(keys, id: \.self) { key in
                        HStack(alignment: .top) {
                            Text(key).font(TypeRole.mono).foregroundStyle(.secondary)
                            Spacer()
                            Text(model.properties[key] ?? "").font(TypeRole.mono).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                    }
                }
                .onChange(of: model.showsProperties) { _, shown in if shown && model.properties.isEmpty { model.loadProperties() } }
            }
            .padding(Space.lg)
        }
        .canvasBackground()
        .task { model.load() }
        .toolbar { }
    }

    private func size(_ s: DeviceInfoDetails.Size?) -> String? { s.map { "\($0.width) × \($0.height)" } }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(TypeRole.section)
            VStack(spacing: Space.xs) { content() }
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?, copyable: Bool = false) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
                if copyable {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).frame(minWidth: 24, minHeight: 24).help("Copy").accessibilityLabel("Copy \(label)")
                }
            }
            .font(TypeRole.secondary)
        }
    }
}
