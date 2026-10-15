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
                TextField("Filter by package", text: $model.search).textFieldStyle(.roundedBorder)
                Toggle("System", isOn: $model.includeSystem).toggleStyle(.checkbox)
                Button { chooseApks() } label: { Image(systemName: "plus") }.help("Install APK…")
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
            }
            .padding(8)
            if let progress = model.installProgress { ProgressView(progress).padding(.horizontal, 8) }
            List(model.visibleApps, selection: Binding(get: { model.selected }, set: { model.select($0) })) { app in
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.packageName).lineLimit(1)
                    Text(app.isSystem ? "System" : "User").font(.caption).foregroundStyle(.secondary)
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
            .overlay { if model.isLoading { ProgressView() } }
            .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])) } }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in handleDrop(providers) }
            Divider()
            detail
        }
        .task { model.load() }
        .confirmationDialog("Clear all data for \(confirmClear ?? "")?", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } })) {
            Button("Clear Data", role: .destructive) { if let package = confirmClear { model.clear(package) } }
        } message: {
            Text("The app will return to its freshly installed state. This can't be undone.")
        }
        .confirmationDialog("Uninstall \(confirmUninstall ?? "")?", isPresented: Binding(get: { confirmUninstall != nil }, set: { if !$0 { confirmUninstall = nil } })) {
            Button("Uninstall", role: .destructive) { if let package = confirmUninstall { model.uninstall(package) } }
        }
    }

    @ViewBuilder private var detail: some View {
        if let package = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(package).font(.headline).textSelection(.enabled)
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
                            Text("Debuggable app: browse its data container in the Files tab using the button below.").font(.caption).foregroundStyle(.secondary)
                            Button("Open Data Container") {
                                NotificationCenter.default.post(name: .openContainer, object: package)
                            }
                        }
                        let runtime = details.permissions.filter(\.isRuntime)
                        if !runtime.isEmpty {
                            Text("Runtime Permissions").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(runtime) { permission in
                                Toggle(permission.name.replacingOccurrences(of: "android.permission.", with: ""), isOn: Binding(
                                    get: { permission.granted ?? false },
                                    set: { model.setPermission(permission.name, granted: $0, package: package) }))
                                    .font(.caption)
                            }
                        }
                        Text("\(details.permissions.count) permissions declared").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.green) }
                }
                .padding(10)
            }
            .frame(maxHeight: 280)
        } else {
            Text("Select an app, or drag and drop an .apk file onto the list to install it.").font(.callout).foregroundStyle(.secondary).padding()
        }
    }

    private func line(_ label: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.caption)
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
