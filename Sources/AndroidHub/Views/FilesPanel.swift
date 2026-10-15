import AdbKit
import SwiftUI

/// Device file browser: browse, transfer and drag files.
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

    private let shortcuts = [("Internal Storage", "/sdcard"), ("Download", "/sdcard/Download"), ("DCIM", "/sdcard/DCIM"), ("Pictures", "/sdcard/Pictures"), ("Documents", "/sdcard/Documents"), ("Movies", "/sdcard/Movies"), ("Temp (tmp)", "/data/local/tmp")]

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(message: model.error)
            HStack(spacing: Space.sm) {
                Button { model.goUp() } label: { Image(systemName: "chevron.up").frame(minWidth: 24, minHeight: 24) }.help("Go to Parent Folder").accessibilityLabel("Go to parent folder")
                TextField("Path", text: $model.path).textFieldStyle(.roundedBorder).font(TypeRole.mono).accessibilityLabel("Path").onSubmit { model.load() }
                Button { model.load() } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 24, minHeight: 24) }.help("Reload").accessibilityLabel("Reload folder")
            }
            .padding(Space.sm)
            HStack {
                if model.containerPackage == nil {
                    Menu("Locations") { ForEach(shortcuts, id: \.1) { name, path in Button(name) { model.load(path) } } }.fixedSize()
                } else {
                    Button("Exit Container") { model.useContainer(nil) }
                }
                Button { pushFiles() } label: { Label("Upload", systemImage: "square.and.arrow.up") }
                Button { pullSelected() } label: { Label("Download", systemImage: "square.and.arrow.down") }.disabled(model.selected.isEmpty)
                Button { showNewFolder = true } label: { Image(systemName: "folder.badge.plus").frame(minWidth: 24, minHeight: 24) }.help("New Folder").accessibilityLabel("New folder").disabled(model.containerPackage != nil)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash").frame(minWidth: 24, minHeight: 24) }.help("Delete").accessibilityLabel("Delete selected items").disabled(model.selected.isEmpty || model.containerPackage != nil)
                Spacer()
            }
            .padding(.horizontal, Space.sm).padding(.bottom, Space.sm).controlSize(.small)
            if let transfer = model.transfer { ProgressView(transfer).padding(.horizontal, Space.sm) }
            if let package = model.containerPackage { Text("Data container: \(package)").font(TypeRole.caption).foregroundStyle(.secondary).padding(.horizontal, Space.sm) }

            List(selection: $model.selected) {
                ForEach(model.entries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc").foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.name).font(TypeRole.body).lineLimit(1).truncationMode(.middle)
                            Text("\(entry.permissionString)  \(entry.modified.formatted(date: .abbreviated, time: .shortened))").font(TypeRole.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if !entry.isDirectory { Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)).font(TypeRole.caption).foregroundStyle(.secondary) }
                    }
                    .tag(entry.name)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.open(entry) }
                    .contextMenu {
                        if entry.isDirectory { Button("Open") { model.open(entry) } }
                        Button("Download…") { model.selected = [entry.name]; pullSelected() }
                        Button("Rename…") { renaming = entry; renameText = entry.name }.disabled(model.containerPackage != nil)
                        Button("Delete", role: .destructive) { model.selected = [entry.name]; confirmDelete = true }.disabled(model.containerPackage != nil)
                    }
                }
            }
            .overlay {
                if model.isLoading {
                    VStack(spacing: Space.sm) {
                        ProgressView()
                        Text("Loading files…").font(TypeRole.caption).foregroundStyle(.secondary)
                    }
                } else if model.entries.isEmpty {
                    StatusMessage(symbol: "folder", title: "Empty Folder", message: "Drag files here to upload them to this folder.")
                }
            }
            .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])) } }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedURLs(providers) { urls in if !urls.isEmpty { model.push(urls) } }
                return true
            }
            if let message = model.message { Label(message, systemImage: "checkmark.circle.fill").font(TypeRole.caption).foregroundStyle(.green).padding(Space.xs) }
        }
        .canvasBackground()
        .task { model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .openContainer)) { note in
            if let package = note.object as? String { model.useContainer(package) }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { if !newFolderName.isEmpty { model.makeFolder(newFolderName) }; newFolderName = "" }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New Name", text: $renameText)
            Button("Rename") { if let old = renaming?.name, !renameText.isEmpty { model.rename(old, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete \(model.selected.count) item(s) from \(model.loadedPath)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete(Array(model.selected)) }
        } message: {
            Text("The selected items will be permanently deleted from the device. This can't be undone.")
        }
    }

    private func pushFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Upload"
        if panel.runModal() == .OK { model.push(panel.urls) }
    }

    private func pullSelected() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { model.pull(Array(model.selected), to: url) }
    }
}
