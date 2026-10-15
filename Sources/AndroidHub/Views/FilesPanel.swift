import AdbKit
import SwiftUI

/// The Android counterpart of Device Hub's DeviceFS mount: browse, transfer and drag files.
struct FilesPanel: View {
    @StateObject private var model: FilesModel
    @State private var isDropTargeted = false
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var renaming: RemoteFileEntry?
    @State private var renameText = ""
    @State private var confirmDelete = false

    init(serial: String, client: AdbClient) {
        _model = StateObject(wrappedValue: FilesModel(serial: serial, client: client))
    }

    private let shortcuts = [("Bộ nhớ trong", "/sdcard"), ("Download", "/sdcard/Download"), ("DCIM", "/sdcard/DCIM"), ("Pictures", "/sdcard/Pictures"), ("Documents", "/sdcard/Documents"), ("Movies", "/sdcard/Movies"), ("Tạm (tmp)", "/data/local/tmp")]

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(message: model.error)
            HStack(spacing: 6) {
                Button { model.goUp() } label: { Image(systemName: "chevron.up") }.help("Lên thư mục cha")
                TextField("Đường dẫn", text: $model.path).textFieldStyle(.roundedBorder).onSubmit { model.load() }
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.help("Tải lại")
            }
            .padding(8)
            HStack {
                if model.containerPackage == nil {
                    Menu("Vị trí") { ForEach(shortcuts, id: \.1) { name, path in Button(name) { model.load(path) } } }.fixedSize()
                } else {
                    Button("Thoát container") { model.useContainer(nil) }
                }
                Button { pushFiles() } label: { Label("Tải lên", systemImage: "square.and.arrow.up") }
                Button { pullSelected() } label: { Label("Tải về", systemImage: "square.and.arrow.down") }.disabled(model.selected.isEmpty)
                Button { showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }.help("Thư mục mới").disabled(model.containerPackage != nil)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.help("Xoá").disabled(model.selected.isEmpty || model.containerPackage != nil)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.bottom, 6).controlSize(.small)
            if let transfer = model.transfer { ProgressView(transfer).padding(.horizontal, 8) }
            if let package = model.containerPackage { Text("Data container: \(package)").font(.caption).foregroundStyle(.secondary) }

            List(selection: $model.selected) {
                ForEach(model.entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc").foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.name).lineLimit(1)
                            Text("\(entry.permissionString)  \(entry.modified.formatted(date: .abbreviated, time: .shortened))").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !entry.isDirectory { Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(entry.name)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.open(entry) }
                    .contextMenu {
                        if entry.isDirectory { Button("Mở") { model.open(entry) } }
                        Button("Tải về…") { model.selected = [entry.name]; pullSelected() }
                        Button("Đổi tên…") { renaming = entry; renameText = entry.name }.disabled(model.containerPackage != nil)
                        Button("Xoá", role: .destructive) { model.selected = [entry.name]; confirmDelete = true }.disabled(model.containerPackage != nil)
                    }
                }
            }
            .overlay { if model.isLoading { ProgressView() } else if model.entries.isEmpty { Text("Thư mục trống").foregroundStyle(.secondary) } }
            .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])) } }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedURLs(providers) { urls in if !urls.isEmpty { model.push(urls) } }
                return true
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.green).padding(4) }
        }
        .task { model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .openContainer)) { note in
            if let package = note.object as? String { model.useContainer(package) }
        }
        .alert("Thư mục mới", isPresented: $showNewFolder) {
            TextField("Tên", text: $newFolderName)
            Button("Tạo") { if !newFolderName.isEmpty { model.makeFolder(newFolderName) }; newFolderName = "" }
            Button("Huỷ", role: .cancel) { newFolderName = "" }
        }
        .alert("Đổi tên", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên mới", text: $renameText)
            Button("Đổi") { if let old = renaming?.name, !renameText.isEmpty { model.rename(old, to: renameText) }; renaming = nil }
            Button("Huỷ", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Xoá \(model.selected.count) mục khỏi \(model.loadedPath)?", isPresented: $confirmDelete) {
            Button("Xoá", role: .destructive) { model.delete(Array(model.selected)) }
        }
    }

    private func pushFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Tải lên"
        if panel.runModal() == .OK { model.push(panel.urls) }
    }

    private func pullSelected() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Lưu vào đây"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { model.pull(Array(model.selected), to: url) }
    }
}
