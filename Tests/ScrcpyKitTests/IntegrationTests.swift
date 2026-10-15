import AdbKit
import CoreMedia
import Foundation
import Testing

@testable import ScrcpyKit

/// End-to-end mirroring against a real emulator:
///
///     ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter ScrcpyKitTests.IntegrationTests
private let serial = ProcessInfo.processInfo.environment["ADBHUB_TEST_SERIAL"]

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var factory = H264SampleFactory()
    private(set) var samples = 0
    private(set) var size: FrameSize?
    private(set) var configPackets = 0

    func handle(_ packet: VideoPacket) {
        if packet.isConfig { lock.withLock { configPackets += 1 } }
        let outputs = lock.withLock { factory.process(packet) }
        for output in outputs {
            switch output {
            case .formatChanged(let s): lock.withLock { size = s }
            case .sample: lock.withLock { samples += 1 }
            }
        }
    }

    var snapshot: (samples: Int, size: FrameSize?, configs: Int) { lock.withLock { (samples, size, configPackets) } }
}

@Suite("scrcpy integration (needs ADBHUB_TEST_SERIAL)", .enabled(if: serial != nil), .serialized)
struct ScrcpyIntegrationTests {
    @Test("handshake, decode-ready samples and a control message round-trip")
    func session() async throws {
        let serial = try #require(serial)
        let client = AdbClient()
        let collector = Collector()

        let session = try await ScrcpySession.start(
            client: client, serial: serial, configuration: ScrcpyConfiguration(maxSize: 720),
            handlers: ScrcpyHandlers(onPacket: { collector.handle($0) }))
        defer { session.stop() }

        #expect(session.initialSize.width > 0 && session.initialSize.height > 0)
        #expect(session.initialSize.width <= 720 || session.initialSize.height <= 720)

        // Ask for a fresh key frame, then wait for frames to arrive.
        session.send(.resetVideo)
        for _ in 0..<50 where collector.snapshot.samples == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        let snapshot = collector.snapshot
        #expect(snapshot.samples > 0)
        #expect(snapshot.configs >= 1)
        #expect(snapshot.size != nil)

        // Control channel: pressing HOME must put the launcher on top.
        session.send(.injectKeycode(action: .down, keycode: 3))
        session.send(.injectKeycode(action: .up, keycode: 3))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let top = try client.run(serial: serial, "dumpsys activity activities | grep -m1 topResumedActivity")
        #expect(top.lowercased().contains("launcher"))
    }

    @Test("the leftover check can actually see a running server")
    func checkerIsNotVacuous() async throws {
        let serial = try #require(serial)
        let client = AdbClient()
        let session = try await ScrcpySession.start(client: client, serial: serial, handlers: ScrcpyHandlers(onPacket: { _ in }))
        defer { session.stop() }
        let running = try client.shell(serial: serial, "ps -A -o ARGS | grep -c '[s]crcpy.Server'")
        #expect((Int(running.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) >= 1)
    }

    @Test("cancelling while the server is still starting aborts the start and leaves nothing behind")
    func cancelWhileStarting() async throws {
        let serial = try #require(serial)
        let client = AdbClient()
        let task = Task {
            try await ScrcpySession.start(client: client, serial: serial, handlers: ScrcpyHandlers(onPacket: { _ in }))
        }
        try await Task.sleep(nanoseconds: 150_000_000)  // the jar push + app_process start take far longer
        task.cancel()
        do {
            let session = try await task.value
            session.stop()
            Issue.record("start completed even though the task was cancelled")
        } catch is CancellationError {
            // expected
        }
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let leftover = try client.shell(serial: serial, "ps -A -o ARGS | grep -c '[s]crcpy.Server'")
        #expect(leftover.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test("stopping ends the session once and leaves no server behind")
    func stopCleansUp() async throws {
        let serial = try #require(serial)
        let client = AdbClient()
        let ended = Counter()
        let session = try await ScrcpySession.start(
            client: client, serial: serial, handlers: ScrcpyHandlers(onPacket: { _ in }, onEnd: { _ in ended.increment() }))
        session.stop()
        session.stop()  // idempotent
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(ended.value == 1)
        // `ps -A` alone prints only the command NAME (app_process); the class lives in ARGS. The `[s]` keeps
        // grep from matching its own command line.
        let leftover = try client.shell(serial: serial, "ps -A -o ARGS | grep -c '[s]crcpy.Server'")
        #expect(leftover.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
