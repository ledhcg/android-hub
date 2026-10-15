import AdbKit
import Foundation

/// The scrcpy-server build this package speaks to. The protocol has no compatibility guarantees, so
/// the jar in `Resources/` and this version string must change together.
public enum ScrcpyServer {
    public static let version = "3.3.4"
    /// Upper bound for one video packet announced by the device (a 4K key frame is a few MiB).
    public static let maxVideoPacketSize = 32 * 1024 * 1024
    public static let remotePath = "/data/local/tmp/scrcpy-server-\(version).jar"
    static let resourceName = "scrcpy-server-\(version).jar"

    public static func jarURL() throws -> URL {
        let fm = FileManager.default
        let bundleName = "AndroidHub_ScrcpyKit.bundle"
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources) }
        // A command-line tool keeps its resource bundle right next to the binary.
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            directories.append(executable)
        }
        var candidates: [URL] = []
        for directory in directories {
            candidates.append(directory.appendingPathComponent(resourceName))
            candidates.append(directory.appendingPathComponent("\(bundleName)/\(resourceName)"))
            candidates.append(directory.appendingPathComponent("\(bundleName)/Contents/Resources/\(resourceName)"))
        }
        if let found = candidates.first(where: { fm.fileExists(atPath: $0.path) }) { return found }
        #if DEBUG
            // Development builds (`swift run`, tests): SwiftPM's generated accessor knows the build directory.
            // It traps when the bundle is missing, so it is only used where the bundle is guaranteed to exist.
            if let url = Bundle.module.url(forResource: "scrcpy-server-\(version)", withExtension: "jar") { return url }
        #endif
        throw ScrcpyError.serverJarMissing
    }
}

public enum ScrcpyError: Error, CustomStringConvertible {
    case serverJarMissing
    case serverExited(String)
    case connectTimeout(String)
    case unsupportedCodec(UInt32)
    case disconnected
    /// A packet header announced more data than any real frame needs; the stream is corrupt or hostile.
    case packetTooLarge(Int)

    public var description: String {
        switch self {
        case .serverJarMissing: "scrcpy-server not found in the app's resources."
        case .serverExited(let log): "scrcpy-server stopped unexpectedly on the device.\n\(log)"
        case .connectTimeout(let log): "Timed out waiting for scrcpy-server to start.\n\(log)"
        case .unsupportedCodec(let id): String(format: "Unsupported video codec: 0x%08x", id)
        case .disconnected: "Lost connection to the device."
        case .packetTooLarge(let size): "The device sent an invalid video packet (\(size) bytes); the connection was closed."
        }
    }
}

public struct ScrcpyConfiguration: Sendable, Equatable {
    /// Longest side of the stream in pixels; 0 keeps the native resolution.
    public var maxSize = 0
    public var maxFPS = 60
    public var videoBitRate = 8_000_000
    public var showTouches = false
    public var stayAwake = false
    public var powerOn = true
    /// Device→Mac clipboard sync (the server pushes clipboard changes over the control socket).
    public var clipboardAutosync = true
    /// Wake a sleeping/dozing display before mirroring. A display that is off produces no frames, and some
    /// ROMs (MIUI) ignore the server's own `power_on` option.
    public var wakeScreen = true

    public init(
        maxSize: Int = 0, maxFPS: Int = 60, videoBitRate: Int = 8_000_000, showTouches: Bool = false,
        stayAwake: Bool = false, powerOn: Bool = true, clipboardAutosync: Bool = true, wakeScreen: Bool = true
    ) {
        self.maxSize = maxSize
        self.maxFPS = maxFPS
        self.videoBitRate = videoBitRate
        self.showTouches = showTouches
        self.stayAwake = stayAwake
        self.powerOn = powerOn
        self.clipboardAutosync = clipboardAutosync
        self.wakeScreen = wakeScreen
    }
}

public struct ScrcpyHandlers: Sendable {
    /// Called on the video reader thread for every packet (config packets included).
    public var onPacket: @Sendable (VideoPacket) -> Void
    public var onDeviceMessage: @Sendable (DeviceMessage) -> Void
    /// Called exactly once when the session ends; `nil` means it was stopped on purpose.
    public var onEnd: @Sendable (Error?) -> Void
    public var onLog: @Sendable (String) -> Void

    public init(
        onPacket: @escaping @Sendable (VideoPacket) -> Void,
        onDeviceMessage: @escaping @Sendable (DeviceMessage) -> Void = { _ in },
        onEnd: @escaping @Sendable (Error?) -> Void = { _ in },
        onLog: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.onPacket = onPacket
        self.onDeviceMessage = onDeviceMessage
        self.onEnd = onEnd
        self.onLog = onLog
    }
}

/// A live mirroring + control connection to one device.
///
/// Lifecycle: push the jar → run it under `app_process` (its lifetime is the shell connection) →
/// connect to its abstract socket through adb (`localabstract:`, no host port) in the fixed order
/// video, control → read the 64-byte device name and the codec header → stream packets.
public final class ScrcpySession: @unchecked Sendable {
    public let serial: String
    public let deviceName: String
    public let initialSize: FrameSize

    private let process: ShellProcess
    private let videoSocket: AdbSocket
    private let controlSocket: AdbSocket
    private let handlers: ScrcpyHandlers
    private let lock = NSLock()
    /// Control writes run here, in order, off the caller's thread: a stalled socket can never freeze the UI
    /// (which sends from the main thread) or block `finish`.
    private let sendQueue = DispatchQueue(label: "scrcpy.control.send", qos: .userInteractive)
    private var finished = false
    private var didStop = false

    private init(
        serial: String, deviceName: String, initialSize: FrameSize, process: ShellProcess,
        videoSocket: AdbSocket, controlSocket: AdbSocket, handlers: ScrcpyHandlers
    ) {
        self.serial = serial
        self.deviceName = deviceName
        self.initialSize = initialSize
        self.process = process
        self.videoSocket = videoSocket
        self.controlSocket = controlSocket
        self.handlers = handlers
    }

    /// Starts a session. Cancelling the calling task aborts the start (and the half-started server on
    /// the device) instead of letting it run to completion in the background.
    public static func start(
        client: AdbClient, serial: String, configuration: ScrcpyConfiguration = ScrcpyConfiguration(),
        handlers: ScrcpyHandlers
    ) async throws -> ScrcpySession {
        let cancel = Flag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try startBlocking(client: client, serial: serial, configuration: configuration, handlers: handlers, cancel: cancel)
            }.value
        } onCancel: {
            cancel.set()
        }
    }

    private static func startBlocking(
        client: AdbClient, serial: String, configuration: ScrcpyConfiguration, handlers: ScrcpyHandlers, cancel: Flag
    ) throws -> ScrcpySession {
        let debug = ProcessInfo.processInfo.environment["ADBHUB_DEBUG"] != nil
        let began = Date()
        func trace(_ message: String) {
            guard debug else { return }
            FileHandle.standardError.write(Data(String(format: "[scrcpy +%.2fs] %@\n", Date().timeIntervalSince(began), message).utf8))
        }

        try client.syncSession(serial: serial).push(try ScrcpyServer.jarURL(), to: ScrcpyServer.remotePath)
        trace("jar pushed")
        if cancel.isSet { throw CancellationError() }
        if configuration.wakeScreen {
            // Best effort: only presses WAKEUP when the display is not awake.
            _ = try? client.shell(
                serial: serial, "dumpsys power | grep -q 'mWakefulness=Awake' || input keyevent KEYCODE_WAKEUP")
            trace("wake requested")
        }

        let scid = UInt32.random(in: 1..<0x7FFF_FFFF)
        let socketName = String(format: "scrcpy_%08x", scid)
        let arguments = [
            "scid=\(String(format: "%08x", scid))", "log_level=info", "tunnel_forward=true", "audio=false",
            "video_codec=h264", "max_size=\(configuration.maxSize)", "max_fps=\(configuration.maxFPS)",
            "video_bit_rate=\(configuration.videoBitRate)", "control=true", "cleanup=true",
            "clipboard_autosync=\(configuration.clipboardAutosync)", "show_touches=\(configuration.showTouches)",
            "stay_awake=\(configuration.stayAwake)", "power_on=\(configuration.powerOn)",
        ]
        let process = client.shellStream(
            serial: serial,
            "CLASSPATH=\(ScrcpyServer.remotePath) app_process / com.genymobile.scrcpy.Server \(ScrcpyServer.version) "
                + arguments.joined(separator: " "))

        // Watch the server's own output: surfaced on failure, forwarded to the UI log otherwise.
        let serverLog = ServerLog()
        let exited = Flag()
        let logTask = Task.detached {
            var pending = ""
            do {
                for try await event in process.events {
                    switch event {
                    case .stdout(let data), .stderr(let data):
                        pending += String(decoding: data, as: UTF8.self)
                        while let newline = pending.firstIndex(of: "\n") {
                            let line = String(pending[..<newline])
                            pending.removeSubrange(...newline)
                            serverLog.append(line)
                            handlers.onLog(line)
                        }
                    case .exit:
                        exited.set()
                    }
                }
            } catch {}
            exited.set()
        }
        _ = logTask

        func failure(_ error: (String) -> ScrcpyError) -> ScrcpyError {
            process.cancel()
            return error(serverLog.text)
        }
        func abortIfCancelled() throws {
            if cancel.isSet {
                process.cancel()
                throw CancellationError()
            }
        }

        // 1. Video socket — retry until the freshly started server is listening. The first accepted
        //    socket also receives one dummy byte, which proves the tunnel really reaches the server.
        var video: AdbSocket?
        var lastError: Error?
        for attempt in 0..<400 {
            try abortIfCancelled()
            if exited.isSet { throw failure(ScrcpyError.serverExited) }
            do {
                let socket = try client.openLocalAbstract(serial: serial, name: socketName)
                socket.setReadTimeout(10)
                _ = try socket.readExactly(1)
                video = socket
                trace("video socket connected after \(attempt + 1) attempt(s)")
                break
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard let video else {
            if let lastError { serverLog.append("last connection attempt failed: \(lastError)") }
            throw failure(ScrcpyError.connectTimeout)
        }

        try abortIfCancelled()
        // 2. Control socket (accepted second).
        let control: AdbSocket
        do { control = try client.openLocalAbstract(serial: serial, name: socketName) } catch {
            throw failure(ScrcpyError.connectTimeout)
        }

        // 3. Device meta (64-byte NUL-padded name) + codec header (codec id, width, height).
        let meta: [UInt8]
        let header: [UInt8]
        do {
            meta = try video.readExactly(64)
            header = try video.readExactly(12)
        } catch { throw failure(ScrcpyError.serverExited) }
        video.setReadTimeout(0)

        let name = String(decoding: meta.prefix { $0 != 0 }, as: UTF8.self)
        let codec = UInt32(header[0]) << 24 | UInt32(header[1]) << 16 | UInt32(header[2]) << 8 | UInt32(header[3])
        guard codec == 0x6832_3634 else { throw failure { _ in ScrcpyError.unsupportedCodec(codec) } }
        let width = Int(header[4]) << 24 | Int(header[5]) << 16 | Int(header[6]) << 8 | Int(header[7])
        let height = Int(header[8]) << 24 | Int(header[9]) << 16 | Int(header[10]) << 8 | Int(header[11])

        try abortIfCancelled()
        let session = ScrcpySession(
            serial: serial, deviceName: name, initialSize: FrameSize(width: width, height: height), process: process,
            videoSocket: video, controlSocket: control, handlers: handlers)
        session.startReaders(exited: exited, serverLog: serverLog)
        trace("session ready \(width)x\(height)")
        return session
    }

    // MARK: Reader threads

    private func startReaders(exited: Flag, serverLog: ServerLog) {
        let videoThread = Thread { [self] in
            do {
                while true {
                    let header = try videoSocket.readExactly(12)
                    var word: UInt64 = 0
                    for byte in header[0..<8] { word = word << 8 | UInt64(byte) }
                    let size = Int(header[8]) << 24 | Int(header[9]) << 16 | Int(header[10]) << 8 | Int(header[11])
                    // The size comes from the device: never allocate on its say-so beyond a sane bound.
                    guard size <= ScrcpyServer.maxVideoPacketSize else { throw ScrcpyError.packetTooLarge(size) }
                    let payload = size > 0 ? try videoSocket.readExactly(size) : []
                    handlers.onPacket(VideoPacket(header: word, data: Data(payload)))
                }
            } catch let error as ScrcpyError {
                finish(stoppedByUser() ? nil : error)
            } catch {
                finish(stoppedByUser() ? nil : (exited.isSet ? ScrcpyError.serverExited(serverLog.text) : ScrcpyError.disconnected))
            }
        }
        videoThread.name = "scrcpy.video"
        videoThread.qualityOfService = .userInteractive
        videoThread.start()

        let controlThread = Thread { [self] in
            var parser = DeviceMessageParser()
            do {
                while true {
                    let chunk = try controlSocket.readSome()
                    if chunk.isEmpty { return }
                    for message in try parser.feed(chunk) { handlers.onDeviceMessage(message) }
                }
            } catch {
                // The control channel dying is reported through the video thread.
            }
        }
        controlThread.name = "scrcpy.control"
        controlThread.start()
    }

    private func stoppedByUser() -> Bool { lock.withLock { didStop } }

    private func finish(_ error: Error?) {
        let shouldNotify = lock.withLock { () -> Bool in
            if finished { return false }
            finished = true
            return true
        }
        guard shouldNotify else { return }
        videoSocket.cancel()
        controlSocket.cancel()
        process.cancel()
        handlers.onEnd(error)
    }

    // MARK: Public API

    /// Queues a control message. Safe from any thread, never blocks, delivered in order; silently
    /// ignored once the session has ended.
    public func send(_ message: ControlMessage) {
        guard lock.withLock({ !finished }) else { return }
        let bytes = message.serialize()
        sendQueue.async { [controlSocket] in try? controlSocket.writeAll(bytes) }
    }

    public func stop() {
        lock.withLock { didStop = true }
        finish(nil)
    }
}

private final class ServerLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) {
        lock.withLock {
            lines.append(line)
            if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        }
    }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
