import Foundation
import Testing

@testable import EmulatorKit

@Suite("AVD config parsing")
struct AvdParsingTests {
    @Test("ini parsing ignores comments and keeps '=' inside values")
    func ini() {
        let parsed = AvdManager.parseIni("# comment\nname=Pixel\npath=/a=b/c\n\nbad line\n")
        #expect(parsed["name"] == "Pixel")
        #expect(parsed["path"] == "/a=b/c")
        #expect(parsed.count == 2)
    }

    @Test("AVD is assembled from avd.ini + config.ini")
    func makeAvd() {
        let avd = AvdManager.makeAVD(
            name: "Pixel_8", directory: "/x/Pixel_8.avd", ini: ["target": "android-37.0"],
            config: [
                "avd.ini.displayname": "Pixel 8", "hw.device.name": "pixel_8", "PlayStore.enabled": "true",
                "hw.lcd.width": "1080", "hw.lcd.height": "2400", "hw.lcd.density": "420", "hw.ramSize": "2048",
                "image.sysdir.1": "system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/",
                "abi.type": "arm64-v8a", "tag.id": "google_apis_playstore",
            ])
        #expect(avd.displayName == "Pixel 8")
        #expect(avd.hasPlayStore)
        #expect(avd.width == 1080 && avd.height == 2400 && avd.density == 420)
        #expect(avd.systemImage == "system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a")
    }

    @Test("launch options map to emulator flags")
    func flags() {
        let options = EmulatorLaunchOptions(headless: true, coldBoot: true, wipeData: true, extraArguments: ["-gpu", "host"])
        #expect(options.arguments == ["-no-window", "-no-snapshot-load", "-wipe-data", "-no-audio", "-no-snapshot-save", "-gpu", "host"])
    }
}

@Suite("AVD API detection")
struct AvdApiTests {
    @Test("a bogus `target=android-0` falls back to the system image path")
    func bogusTarget() {
        let avd = AvdManager.makeAVD(
            name: "X", directory: "/x", ini: ["target": "android-0"],
            config: ["image.sysdir.1": "system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/"])
        #expect(avd.apiTarget == "android-37.0")
    }

    @Test("a sane target is kept")
    func saneTarget() {
        let avd = AvdManager.makeAVD(name: "X", directory: "/x", ini: ["target": "android-34"], config: [:])
        #expect(avd.apiTarget == "android-34")
    }
}

@Suite("AVD safety")
struct AvdSafetyTests {
    private func makeAvd(lock: String?) throws -> (AvdManager, AVD, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("avd-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("T.avd")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "path=\(directory.path)\ntarget=android-34\n".write(to: root.appendingPathComponent("T.ini"), atomically: true, encoding: .utf8)
        try "AvdId=T\n".write(to: directory.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        for name in ["userdata-qemu.img.qcow2", "sdcard.img"] { try Data([1]).write(to: directory.appendingPathComponent(name)) }
        if let lock { try lock.write(to: directory.appendingPathComponent("hardware-qemu.ini.lock"), atomically: true, encoding: .utf8) }
        let manager = AvdManager(sdk: AndroidSDK(root: root), avdHome: root)
        return (manager, try #require(try manager.listAVDs().first), root)
    }

    @Test("a lock file naming a live pid means the AVD is running; a dead pid does not")
    func running() throws {
        let alive = try makeAvd(lock: "\(getpid())\0")
        defer { try? FileManager.default.removeItem(at: alive.2) }
        #expect(alive.0.isRunning(alive.1))
        let stale = try makeAvd(lock: "999999\0")
        defer { try? FileManager.default.removeItem(at: stale.2) }
        #expect(!stale.0.isRunning(stale.1))
        let none = try makeAvd(lock: nil)
        defer { try? FileManager.default.removeItem(at: none.2) }
        #expect(!none.0.isRunning(none.1))
    }

    @Test("wipe and delete refuse while the emulator is alive")
    func refuses() throws {
        let (manager, _, root) = try makeAvd(lock: "\(getpid())")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: EmulatorError.stillRunning("T")) { try manager.wipeData(name: "T") }
        #expect(throws: EmulatorError.stillRunning("T")) { try manager.deleteAVD(name: "T") }
    }

    @Test("wipe removes user data but keeps the SD card image")
    func wipeKeepsSdcard() throws {
        let (manager, avd, root) = try makeAvd(lock: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        try manager.wipeData(name: "T")
        #expect(!FileManager.default.fileExists(atPath: avd.directory + "/userdata-qemu.img.qcow2"))
        #expect(FileManager.default.fileExists(atPath: avd.directory + "/sdcard.img"))
    }
}
