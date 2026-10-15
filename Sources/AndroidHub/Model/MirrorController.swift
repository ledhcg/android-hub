import AVFoundation
import AdbKit
import AppKit
import ScrcpyKit

/// Owns one device's live screen: the scrcpy session, the canvas view, recording and screenshots.
@MainActor
final class MirrorController: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var frameSize: FrameSize?
    @Published private(set) var isRecording = false
    @Published var markedText = ""
    @Published var toast: String?

    let serial: String
    private let hub = MirrorHub()
    private let client: AdbClient
    private var session: ScrcpySession?
    private var recorder: ScreenRecorder?
    /// Records from the packet stream itself, so it works with any number of canvases (or none).
    private let recordingTap = RecordingTap()
    private var toastTask: Task<Void, Never>?
    /// Bumped by every start/stop so a slow `ScrcpySession.start` that finishes after Cancel is discarded.
    private var generation = 0
    private var startTask: Task<Void, Never>?

    init(serial: String, client: AdbClient) {
        self.serial = serial
        self.client = client
    }

    /// A new canvas for this device. Every window that shows the device owns one; they all share the session.
    func makeView() -> MirrorNSView {
        let view = MirrorNSView(frame: .zero)
        view.sendControl = { [weak self] message in self?.send(message) }
        view.onFrameSizeChange = { [weak self] size in
            guard let self else { return }
            self.frameSize = size
            if case .starting = self.state { self.state = .running }
        }
        view.onMarkedTextChange = { [weak self] text in self?.markedText = text }
        hub.add(view)
        if session != nil { session?.send(.resetVideo) }  // a joining canvas needs a fresh key frame
        return view
    }

    func discard(_ view: MirrorNSView) { hub.remove(view) }

    var isRunning: Bool { state == .running || state == .starting }

    // MARK: Lifecycle

    // Autosync off: it would echo every paste back into the Mac clipboard. Cmd+C/X ask for the clipboard explicitly.
    func start(configuration: ScrcpyConfiguration = ScrcpyConfiguration(clipboardAutosync: false)) {
        guard !isRunning else { return }
        state = .starting
        hub.reset()
        generation += 1
        let myGeneration = generation
        let hub = self.hub
        let tap = self.recordingTap
        startTask = Task {
            do {
                let session = try await ScrcpySession.start(
                    client: client, serial: serial, configuration: configuration,
                    handlers: ScrcpyHandlers(
                        onPacket: { hub.dispatch($0); tap.handle($0) },
                        onDeviceMessage: { [weak self] message in
                            Task { @MainActor in self?.handle(deviceMessage: message) }
                        },
                        onEnd: { [weak self] error in
                            Task { @MainActor in self?.sessionEnded(error) }
                        }))
                guard self.generation == myGeneration else {
                    session.stop()  // cancelled while the server was still starting
                    return
                }
                self.session = session
                // The codec header already told us the frame size, so the canvases can be created now
                // (they replay the hub's cached config packet and ask for a fresh key frame).
                self.frameSize = session.initialSize
                self.state = .running
                // Nudge the encoder so a static screen still produces a first frame promptly.
                session.send(.resetVideo)
            } catch is CancellationError {
                // Cancelled by `stop()`, which already reset the state.
            } catch {
                if self.generation == myGeneration { self.state = .failed(error.userMessage) }
            }
        }
    }

    func stop() {
        generation += 1
        startTask?.cancel()  // aborts a server that is still starting on the device
        startTask = nil
        if isRecording { stopRecording() }
        session?.stop()
        session = nil
        state = .idle
        frameSize = nil
        hub.reset()
    }

    /// Called when the app quits: finalise an in-progress recording (an MP4 without its `moov` atom is
    /// unplayable) and shut the device-side server down.
    func shutdownBlocking() {
        let recorder = self.recorder
        self.recorder = nil
        recordingTap.set(nil)
        isRecording = false
        if let recorder {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                _ = await recorder.finish()
                done.signal()
            }
            _ = done.wait(timeout: .now() + 5)
        }
        generation += 1
        startTask?.cancel()
        session?.stop()
        session = nil
    }

    private func sessionEnded(_ error: Error?) {
        if isRecording { stopRecording() }
        session = nil
        frameSize = nil
        hub.reset()
        if let error { state = .failed(error.userMessage) } else { state = .idle }
    }

    private func handle(deviceMessage: DeviceMessage) {
        if case .clipboard(let text) = deviceMessage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showToast("Copied clipboard from device")
        }
    }

    // MARK: Input

    func send(_ message: ControlMessage) { session?.send(message) }

    /// Presses a bezel/navigation button through the control socket (instant, no adb round trip).
    func press(_ button: DeviceButton) {
        switch button {
        case .back:
            send(.backOrScreenOn(.down))
            send(.backOrScreenOn(.up))
        case .notifications: send(.expandNotificationPanel)
        case .quickSettings: send(.expandSettingsPanel)
        case .collapsePanels: send(.collapsePanels)
        default:
            guard let code = button.keycode else { return }
            send(.injectKeycode(action: .down, keycode: Int32(code)))
            send(.injectKeycode(action: .up, keycode: Int32(code)))
        }
    }

    func rotateDevice() { send(.rotateDevice) }

    /// Presses a key repeatedly while a button is held (volume).
    func tapKey(_ keycode: Int32) {
        send(.injectKeycode(action: .down, keycode: keycode))
        send(.injectKeycode(action: .up, keycode: keycode))
    }

    // MARK: Capture

    func screenshot(deviceName: String) {
        let client = self.client
        let serial = self.serial
        Task {
            do {
                let png = try await offMain { try client.screenshot(serial: serial) }
                let url = desktopURL("Screenshot \(deviceName) \(fileTimestamp()).png")
                try png.write(to: url)
                if let image = NSImage(data: png) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                showToast("Saved \(url.lastPathComponent) and copied to clipboard")
            } catch {
                showToast("Screenshot failed: \(error.userMessage)")
            }
        }
    }

    func startRecording(deviceName: String) {
        guard session != nil, !isRecording else { return }
        let url = desktopURL("Screen Recording \(deviceName) \(fileTimestamp()).mp4")
        let recorder = PacketRecorder(url: url)
        recordingTap.set(recorder)
        self.recorder = recorder.recorder
        isRecording = true
        send(.resetVideo)  // guarantees a key frame to start the file on
    }

    func stopRecording() {
        guard isRecording, let recorder else { return }
        isRecording = false
        recordingTap.set(nil)
        self.recorder = nil
        Task {
            let files = await recorder.finish()
            if let file = files.first {
                showToast("Saved \(file.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } else {
                showToast("No frame to save")
            }
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

/// Lets the video thread feed whichever recorder is active without touching main-actor state.
final class RecordingTap: @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: PacketRecorder?

    func set(_ recorder: PacketRecorder?) { lock.withLock { self.recorder = recorder } }
    func handle(_ packet: VideoPacket) { lock.withLock { recorder }?.handle(packet) }
}
