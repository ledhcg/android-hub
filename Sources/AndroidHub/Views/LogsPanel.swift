import AdbKit
import SwiftUI

struct LogsPanel: View {
    @StateObject private var model: LogsModel
    @State private var autoScroll = true

    init(serial: String, client: AdbClient) {
        _model = StateObject(wrappedValue: LogsModel(serial: serial, client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(message: model.error)
            HStack {
                TextField("Search log", text: $model.filter.text).textFieldStyle(.roundedBorder)
                Picker("Level", selection: $model.filter.minimumLevel) {
                    ForEach(LogLevel.allCases.filter { $0 != .silent }, id: \.self) { Text(String($0.rawValue)).tag($0) }
                }.frame(width: 70).help("Minimum log level")
            }
            .padding(8)
            HStack(spacing: 8) {
                TextField("Tag", text: $model.filter.tag).textFieldStyle(.roundedBorder).frame(maxWidth: 110)
                Button { model.togglePause() } label: { Image(systemName: model.isPaused ? "play.fill" : "pause.fill") }.help(model.isPaused ? "Resume" : "Pause")
                Button { model.clear() } label: { Image(systemName: "trash") }.help("Clear Log")
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }.help("Save displayed log")
                Toggle("Auto-Scroll", isOn: $autoScroll).toggleStyle(.checkbox)
                Spacer()
                Text("\(model.visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.bottom, 6).controlSize(.small)
            Divider()
            ScrollViewReader { proxy in
                List(model.visible.suffix(1500)) { entry in
                    Text(attributed(entry)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(entry.id)
                        .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .listStyle(.plain)
                .onChange(of: model.visible.last?.id) { id in
                    if autoScroll, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func attributed(_ entry: LogEntry) -> AttributedString {
        var text = AttributedString("\(entry.timestamp.suffix(12)) \(entry.level.rawValue) \(entry.tag): \(entry.message)")
        switch entry.level {
        case .error, .fatal: text.foregroundColor = .red
        case .warning: text.foregroundColor = .orange
        case .debug, .verbose: text.foregroundColor = .secondary
        default: break
        }
        return text
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "logcat-\(model.serial).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.text(for: model.visible).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct DiagnosticsPanel: View {
    @StateObject private var model: DiagnosticsModel
    @State private var includeBugReport = false

    init(serial: String, client: AdbClient) {
        _model = StateObject(wrappedValue: DiagnosticsModel(serial: serial, client: client))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ErrorBanner(message: model.error)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Collect Diagnostic Files").font(.headline)
                    Text("getprop, logcat, dumpsys, recent crashes/ANRs, and a screenshot.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Include full bugreport (takes a few minutes)", isOn: $includeBugReport)
                    Button("Collect…") { choose { model.collect(to: $0, includeBugReport: includeBugReport) } }.disabled(model.progress != nil)
                    if let progress = model.progress { ProgressView(progress) }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.green) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Crashes & ANRs").font(.headline)
                    HStack {
                        Picker("Type", selection: $model.dropBoxTag) {
                            Text("App crash").tag(DropBoxTag.appCrash)
                            Text("App ANR").tag(DropBoxTag.appANR)
                            Text("Native crash").tag(DropBoxTag.appNativeCrash)
                            Text("System app crash").tag(DropBoxTag.systemAppCrash)
                            Text("System server crash").tag(DropBoxTag.systemServerCrash)
                            Text("StrictMode").tag(DropBoxTag.strictMode)
                        }.labelsHidden()
                        Button("Load") { model.loadDropBox() }
                    }
                    textBox(model.dropBoxText, placeholder: "Click Load to view.")
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("dumpsys").font(.headline)
                    HStack {
                        Picker("Service", selection: $model.selectedService) {
                            Text("(all)").tag("")
                            ForEach(model.services, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                        Button("Run") { model.dump(model.selectedService) }
                    }
                    textBox(model.dumpText, placeholder: "Choose a service, then click Run.")
                }
            }
            .padding(12)
        }
        .task { model.loadServices(); model.loadDropBox() }
    }

    private func textBox(_ text: String, placeholder: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : String(text.prefix(60_000))).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160).padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func choose(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }
}
