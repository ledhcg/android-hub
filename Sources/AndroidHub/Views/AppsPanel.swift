import AdbKit
import SwiftUI
import UniformTypeIdentifiers

/// Device Hub's Apps inspector: find, install and remove apps — plus launch/clear/permissions.
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
                TextField("Lọc theo package", text: $model.search).textFieldStyle(.roundedBorder)
                Toggle("Hệ thống", isOn: $model.includeSystem).toggleStyle(.checkbox)
                Button { chooseApks() } label: { Image(systemName: "plus") }.help("Cài APK…")
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.help("Tải lại")
            }
            .padding(8)
            if let progress = model.installProgress { ProgressView(progress).padding(.horizontal, 8) }
            List(model.visibleApps, selection: Binding(get: { model.selected }, set: { model.select($0) })) { app in
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.packageName).lineLimit(1)
                    Text(app.isSystem ? "Hệ thống" : "Người dùng").font(.caption).foregroundStyle(.secondary)
                }
                .tag(app.packageName)
                .contextMenu {
                    Button("Mở") { model.launch(app.packageName) }
                    Button("Buộc dừng") { model.stop(app.packageName) }
                    Button("Xoá dữ liệu…") { confirmClear = app.packageName }
                    Button("Gỡ cài đặt…", role: .destructive) { confirmUninstall = app.packageName }
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
        .confirmationDialog("Xoá toàn bộ dữ liệu của \(confirmClear ?? "")?", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } })) {
            Button("Xoá dữ liệu", role: .destructive) { if let package = confirmClear { model.clear(package) } }
        } message: {
            Text("Ứng dụng sẽ trở về trạng thái mới cài. Không thể hoàn tác.")
        }
        .confirmationDialog("Gỡ \(confirmUninstall ?? "")?", isPresented: Binding(get: { confirmUninstall != nil }, set: { if !$0 { confirmUninstall = nil } })) {
            Button("Gỡ cài đặt", role: .destructive) { if let package = confirmUninstall { model.uninstall(package) } }
        }
    }

    @ViewBuilder private var detail: some View {
        if let package = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(package).font(.headline).textSelection(.enabled)
                    HStack {
                        Button("Mở") { model.launch(package) }
                        Button("Dừng") { model.stop(package) }
                        Button("Xoá dữ liệu…") { confirmClear = package }
                        Button("Thông tin") { model.openInfo(package) }
                    }
                    HStack {
                        Button("Lấy APK") { chooseDirectory { model.extract(package, to: $0) } }
                        Button("Gỡ…", role: .destructive) { confirmUninstall = package }
                    }
                    if let details = model.details {
                        Group {
                            line("Phiên bản", [details.versionName, details.versionCode.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                            line("minSdk / targetSdk", "\(details.minSdk.map(String.init) ?? "?") / \(details.targetSdk.map(String.init) ?? "?")")
                            line("Cài lần đầu", details.firstInstall)
                            line("Cập nhật", details.lastUpdate)
                            line("Nguồn cài", details.installer)
                            line("Data dir", details.dataDirectory)
                            line("Debuggable", details.isDebuggable ? "Có" : "Không")
                        }
                        if details.isDebuggable {
                            Text("App debuggable: duyệt data container ở tab Tệp bằng nút bên dưới.").font(.caption).foregroundStyle(.secondary)
                            Button("Mở data container") {
                                NotificationCenter.default.post(name: .openContainer, object: package)
                            }
                        }
                        let runtime = details.permissions.filter(\.isRuntime)
                        if !runtime.isEmpty {
                            Text("Quyền runtime").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(runtime) { permission in
                                Toggle(permission.name.replacingOccurrences(of: "android.permission.", with: ""), isOn: Binding(
                                    get: { permission.granted ?? false },
                                    set: { model.setPermission(permission.name, granted: $0, package: package) }))
                                    .font(.caption)
                            }
                        }
                        Text("\(details.permissions.count) quyền được khai báo").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.green) }
                }
                .padding(10)
            }
            .frame(maxHeight: 280)
        } else {
            Text("Chọn một ứng dụng, hoặc kéo-thả file .apk vào danh sách để cài.").font(.callout).foregroundStyle(.secondary).padding()
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
        panel.message = "Chọn một APK, hoặc nhiều APK nếu là split APK"
        if panel.runModal() == .OK { model.install(panel.urls) }
    }

    private func chooseDirectory(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Chọn thư mục"
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
