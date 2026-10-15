import Foundation
import Testing

@testable import AdbKit

/// Runs against a real device/emulator, and only when asked:
///
///     ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter IntegrationTests
///
/// Point it at an EMULATOR — these tests change settings and write files (they clean up after themselves).
private let serial = ProcessInfo.processInfo.environment["ADBHUB_TEST_SERIAL"]

@Suite("integration (needs ADBHUB_TEST_SERIAL)", .enabled(if: serial != nil), .serialized)
struct IntegrationTests {
    let client = AdbClient()

    @Test("the device is listed and ready")
    func listed() throws {
        let devices = try client.devices(enrichWithUSB: false)
        let device = try #require(devices.first { $0.serial == serial })
        #expect(device.isReady)
    }

    @Test("shell v2 separates stdout, stderr and the exit code")
    func shellV2() throws {
        let serial = try #require(serial)
        let result = try client.shell(serial: serial, "echo out; echo err 1>&2; exit 3")
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
        #expect(result.exitCode == 3)
    }

    @Test("binary-safe shell output")
    func binary() throws {
        let serial = try #require(serial)
        let data = try client.shellData(serial: serial, "head -c 100000 /dev/zero")
        #expect(data.count == 100_000 && data.allSatisfy { $0 == 0 })
    }

    @Test("sync push → stat → pull round-trips bytes exactly, including > 64 KiB")
    func syncRoundTrip() throws {
        let serial = try #require(serial)
        var payload = Data(count: 300_000)
        for index in payload.indices { payload[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7) }
        let remote = "/data/local/tmp/androidhub-it-\(UUID().uuidString.prefix(8)).bin"
        defer { _ = try? client.shell(serial: serial, "rm -f \(remote)") }

        try client.syncSession(serial: serial).push(payload, to: remote)
        let entry = try #require(try client.syncSession(serial: serial).stat(remote))
        #expect(entry.size == 300_000 && entry.isRegularFile)
        #expect(try client.syncSession(serial: serial).pullData(remote) == payload)
        #expect(try client.syncSession(serial: serial).stat(remote + ".missing") == nil)
    }

    @Test("settings snapshot reads and a change round-trips")
    func settings() throws {
        let serial = try #require(serial)
        let before = try client.settingsSnapshot(serial: serial)
        let target: Double = before.fontScale == 1.15 ? 1.0 : 1.15
        defer { try? client.apply(.fontScale(before.fontScale ?? 1.0), serial: serial) }
        try client.apply(.fontScale(target), serial: serial)
        #expect(try client.settingsSnapshot(serial: serial).fontScale == target)
    }

    @Test("device info and screenshot")
    func infoAndScreenshot() throws {
        let serial = try #require(serial)
        let info = try client.deviceInfo(serial: serial)
        #expect(info.sdkInt != nil && info.physicalSize != nil)
        let png = try client.screenshot(serial: serial)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("installed apps and details agree")
    func apps() throws {
        let serial = try #require(serial)
        let apps = try client.installedApps(serial: serial)
        let settings = try #require(apps.first { $0.packageName == "com.android.settings" })
        #expect(settings.isSystem)
        let details = try client.appDetails(serial: serial, package: settings.packageName)
        #expect(details.versionName != nil)
    }

    @Test("an unknown serial surfaces a typed error")
    func unknownDevice() {
        #expect(throws: AdbError.self) { try client.shell(serial: "no-such-device", "true") }
    }

    @Test("logcat streams entries and cancels cleanly")
    func logs() async throws {
        let serial = try #require(serial)
        var count = 0
        for try await _ in try client.logStream(serial: serial, backlog: 50) {
            count += 1
            if count >= 5 { break }
        }
        #expect(count == 5)
    }
}
