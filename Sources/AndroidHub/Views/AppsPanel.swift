import AdbKit
import SwiftUI
import UniformTypeIdentifiers

/// Apps inspector: find, install and remove apps — plus launch/clear/permissions.
struct AppsPanel: View {
    @StateObject private var model: AppsModel
    @State private var isDropTargeted = false
    @State private var confirmUninstall: String?
    @State private var confirmClear: String?
    @State private var showContainer = false
    @EnvironmentObject var store: DeviceStore

    init(serial: String, client: AdbClient) {
        _model = StateObject(wrappedValue: AppsModel(serial: serial, client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(message: model.error)
            HStack {
                TextField("Filter by package", text: $model.search).textFieldStyle(.roundedBorder).accessibilityLabel("Filter by package")
                Toggle("System", isOn: $model.includeSystem).toggleStyle(.checkbox)
                Button { chooseApks() } label: { Image(systemName: "plus").frame(minWidth: 24, minHeight: 24) }.help("Install APK…").accessibilityLabel("Install APK")
                Button { model.load() } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 24, minHeight: 24) }.help("Reload").accessibilityLabel("Reload apps")
            }
            .padding(Space.sm)
            if let progress = model.installProgress { ProgressView(progress).padding(.horizontal, Space.sm) }
            List(model.visibleApps, selection: Binding(get: { model.selected }, set: { model.select($0) })) { app in
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.packageName).font(TypeRole.body).lineLimit(1).truncationMode(.middle)
                    Text(app.isSystem ? "System" : "User").font(TypeRole.caption).foregroundStyle(.secondary)
                }
                .tag(app.packageName)
                .contextMenu {
                    Button("Open") { model.launch(app.packageName) }
                    Button("Force Stop") { model.stop(app.packageName) }
                    Button("Clear Data…") { confirmClear = app.packageName }
                    Button("Uninstall…", role: .destructive) { confirmUninstall = app.packageName }
                }
            }
            .frame(minHeight: 120)
            .overlay {
                if model.isLoading {
                    VStack(spacing: Space.sm) {
                        ProgressView()
                        Text("Loading apps…").font(TypeRole.caption).foregroundStyle(.secondary)
                    }
                } else if model.visibleApps.isEmpty {
                    StatusMessage(symbol: "square.grid.2x2", title: "No Apps", message: "No apps match the current filter. Drag an .apk file here to install one.")
                }
            }
            .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])) } }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in handleDrop(providers) }
            Divider()
            detail
        }
        .canvasBackground()
        .task { model.load() }
        .confirmationDialog("Clear all data for \(confirmClear ?? "")?", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } })) {
            Button("Clear Data", role: .destructive) { if let package = confirmClear { model.clear(package) } }
        } message: {
            Text("The app will return to its freshly installed state. This can't be undone.")
        }
        .confirmationDialog("Uninstall \(confirmUninstall ?? "")?", isPresented: Binding(get: { confirmUninstall != nil }, set: { if !$0 { confirmUninstall = nil } })) {
            Button("Uninstall", role: .destructive) { if let package = confirmUninstall { model.uninstall(package) } }
        } message: {
            Text("The app and its data will be removed from the device. This can't be undone.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let package = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(package).font(TypeRole.section).textSelection(.enabled)
                    HStack {
                        Button("Open") { model.launch(package) }
                        Button("Stop") { model.stop(package) }
                        Button("Clear Data…") { confirmClear = package }
                        Button("Info") { model.openInfo(package) }
                    }
                    HStack {
                        Button("Pull APK") { chooseDirectory { model.extract(package, to: $0) } }
                        Button("Uninstall…", role: .destructive) { confirmUninstall = package }
                    }
                    if let details = model.details {
                        Group {
                            line("Version", [details.versionName, details.versionCode.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                            line("minSdk / targetSdk", "\(details.minSdk.map(String.init) ?? "?") / \(details.targetSdk.map(String.init) ?? "?")")
                            line("First Installed", details.firstInstall)
                            line("Last Updated", details.lastUpdate)
                            line("Installer", details.installer)
                            line("Data dir", details.dataDirectory)
                            line("Debuggable", details.isDebuggable ? "Yes" : "No")
                        }
                        if details.isDebuggable {
                            Text("Debuggable app: browse its data container in the Files tab using the button below.").font(TypeRole.caption).foregroundStyle(.secondary)
                            Button("Open Data Container") {
                                NotificationCenter.default.post(name: .openContainer, object: package)
                            }
                        }
                        let runtime = details.permissions.filter(\.isRuntime)
                        if !runtime.isEmpty {
                            Text("Runtime Permissions").font(TypeRole.section).padding(.top, Space.xs)
                            ForEach(runtime) { permission in
                                Toggle(permission.name.replacingOccurrences(of: "android.permission.", with: ""), isOn: Binding(
                                    get: { permission.granted ?? false },
                                    set: { model.setPermission(permission.name, granted: $0, package: package) }))
                                    .font(TypeRole.caption)
                            }
                        }
                        Text("\(details.permissions.count) permissions declared").font(TypeRole.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let message = model.message { Label(message, systemImage: "checkmark.circle.fill").font(TypeRole.caption).foregroundStyle(.green) }
                }
                .padding(Space.md)
            }
            .frame(maxHeight: 280)
        } else {
            Text("Select an app, or drag and drop an .apk file onto the list to install it.").font(TypeRole.secondary).foregroundStyle(.secondary).padding(Space.lg)
        }
    }

    private func line(_ label: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(TypeRole.caption)
            }
        }
    }

    private func chooseApks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Choose an APK, or several APKs for a split APK"
        if panel.runModal() == .OK { model.install(panel.urls) }
    }

    private func chooseDirectory(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        loadDroppedURLs(providers) { urls in
            let apks = urls.filter { $0.pathExtension.lowercased() == "apk" }
            if !apks.isEmpty { model.install(apks) }
        }
        return true
    }
}

extension Notification.Name {
    static let openContainer = Notification.Name("androidhub.openContainer")
}
