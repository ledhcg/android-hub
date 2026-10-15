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
                TextField("Search log", text: $model.filter.text).textFieldStyle(.roundedBorder).accessibilityLabel("Search log")
                Picker("Level", selection: $model.filter.minimumLevel) {
                    ForEach(LogLevel.allCases.filter { $0 != .silent }, id: \.self) { Text(String($0.rawValue)).tag($0) }
                }.fixedSize().help("Minimum log level")
            }
            .padding(Space.sm)
            HStack(spacing: Space.sm) {
                TextField("Tag", text: $model.filter.tag).textFieldStyle(.roundedBorder).frame(maxWidth: 110).accessibilityLabel("Tag filter")
                Button { model.togglePause() } label: { Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(minWidth: 24, minHeight: 24) }.help(model.isPaused ? "Resume" : "Pause").accessibilityLabel(model.isPaused ? "Resume log" : "Pause log")
                Button { model.clear() } label: { Image(systemName: "trash").frame(minWidth: 24, minHeight: 24) }.help("Clear Log").accessibilityLabel("Clear log")
                Button { save() } label: { Image(systemName: "square.and.arrow.down").frame(minWidth: 24, minHeight: 24) }.help("Save displayed log").accessibilityLabel("Save displayed log")
                Toggle("Auto-Scroll", isOn: $autoScroll).toggleStyle(.checkbox)
                Spacer()
                Text("\(model.visible.count)").font(TypeRole.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.sm).padding(.bottom, Space.sm).controlSize(.small)
            Divider()
            ScrollViewReader { proxy in
                List(model.visible.suffix(1500)) { entry in
                    Text(attributed(entry)).font(TypeRole.mono).textSelection(.enabled).id(entry.id)
                        .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .listStyle(.plain)
                .overlay {
                    if model.visible.isEmpty {
                        StatusMessage(symbol: "text.alignleft", title: "No Log Entries", message: model.isPaused ? "Logging is paused. Resume to see new entries." : "Waiting for log output, or no entries match the current filters.")
                    }
                }
                .onChange(of: model.visible.last?.id) { _, id in
                    if autoScroll, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .canvasBackground()
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
            VStack(alignment: .leading, spacing: Space.lg) {
                ErrorBanner(message: model.error)
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Collect Diagnostic Files").font(TypeRole.section)
                    Text("getprop, logcat, dumpsys, recent crashes/ANRs, and a screenshot.").font(TypeRole.caption).foregroundStyle(.secondary)
                    Toggle("Include full bugreport (takes a few minutes)", isOn: $includeBugReport)
                    Button("Collect…") { choose { model.collect(to: $0, includeBugReport: includeBugReport) } }.disabled(model.progress != nil)
                    if let progress = model.progress { ProgressView(progress) }
                    if let message = model.message { Label(message, systemImage: "checkmark.circle.fill").font(TypeRole.caption).foregroundStyle(.green) }
                }
                Divider()
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Recent Crashes & ANRs").font(TypeRole.section)
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
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("dumpsys").font(TypeRole.section)
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
            .padding(Space.lg)
        }
        .canvasBackground()
        .task { model.loadServices(); model.loadDropBox() }
    }

    private func textBox(_ text: String, placeholder: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : String(text.prefix(60_000))).font(TypeRole.mono)
                .foregroundStyle(text.isEmpty ? .secondary : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160).wellStyle()
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
