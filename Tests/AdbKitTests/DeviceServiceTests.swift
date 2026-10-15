import Foundation
import Testing

@testable import AdbKit

@Suite("shell command builders")
struct SettingChangeTests {
    @Test("appearance, rotation and animation map to the exact shell commands")
    func basics() {
        #expect(SettingChange.appearance(.dark).commands == ["cmd uimode night yes"])
        #expect(SettingChange.appearance(.light).commands == ["cmd uimode night no"])
        #expect(SettingChange.appearance(.auto).commands == ["cmd uimode night auto"])
        #expect(
            SettingChange.rotation(.landscapeLeft).commands == [
                "settings put system accelerometer_rotation 0", "settings put system user_rotation 1",
            ])
        #expect(SettingChange.animationScale(10).commands.count == 3)
        #expect(SettingChange.animationScale(0.5).commands.allSatisfy { $0.hasSuffix(" 0.5") })
        #expect(SettingChange.fontScale(1.30).commands == ["settings put system font_scale 1.3"])
        #expect(SettingChange.displaySize(width: 720, height: 1280).commands == ["wm size 720x1280"])
        #expect(SettingChange.resetDisplayDensity.commands == ["wm density reset"])
    }

    @Test("values are clamped where the platform would reject them")
    func clamping() {
        #expect(SettingChange.brightness(999).commands.last == "settings put system screen_brightness 255")
        #expect(SettingChange.brightness(-5).commands.last == "settings put system screen_brightness 0")
        #expect(SettingChange.batteryLevel(150).commands == ["dumpsys battery set level 100"])
    }

    @Test("user text is shell-quoted, including embedded single quotes")
    func quoting() {
        #expect(SettingChange.shellQuote("a b") == "'a b'")
        #expect(SettingChange.shellQuote("it's") == "'it'\\''s'")
        let locale = SettingChange.appLocale(package: "com.x; reboot", languageTag: "vi-VN").commands[0]
        #expect(locale == "cmd locale set-app-locales 'com.x; reboot' --locales 'vi-VN'")
        let zone = SettingChange.timeZone("Asia/Tokyo'; rm -rf /; '").commands[0]
        #expect(zone.contains("'Asia/Tokyo'\\''; rm -rf /; '\\'''"))
    }

    @Test("location uses lon-first `geo fix` on the emulator and a test provider on hardware")
    func location() {
        let change = SettingChange.location(latitude: 10.7769, longitude: 106.7009)
        #expect(change.emulatorConsole == ["geo fix 106.7009 10.7769"])
        #expect(change.commands[0].contains("--location 10.7769,106.7009"))
        #expect(SettingChange.emulatorNetworkSpeed("edge").isEmulatorOnly)
    }

    @Test("decimal formatting trims trailing zeros")
    func decimals() {
        #expect(SettingChange.decimal(1.0) == "1")
        #expect(SettingChange.decimal(1.50) == "1.5")
        #expect(SettingChange.decimal(0.85) == "0.85")
    }
}

@Suite("settings snapshot parsing")
struct SettingsSnapshotTests {
    static let sample = """
        N:Night mode: yes
        S:font_scale=1.3
        S:window_animation_scale=0.5
        S:accelerometer_rotation=0
        S:user_rotation=1
        S:wifi_on=1
        S:mobile_data=null
        S:airplane_mode_on=0
        S:bluetooth_on=0
        S:screen_brightness=150
        S:screen_brightness_mode=0
        S:stay_on_while_plugged_in=7
        S:show_touches=null
        S:pointer_location=1
        S:screen_off_timeout=60000
        S:accessibility_display_inversion_enabled=null
        S:high_text_contrast_enabled=1
        S:accessibility_display_daltonizer_enabled=1
        S:accessibility_display_daltonizer=12
        S:always_finish_activities=null
        V:[V] volume is 7 in range [0..15]
        P:locale=
        P:fallbackLocale=en-US
        P:timezone=Asia/Ho_Chi_Minh
        """

    @Test("typed values come out of the key=value dump")
    func parse() {
        let snapshot = DeviceSettingsSnapshot.parse(Self.sample)
        #expect(snapshot.appearance == .dark)
        #expect(snapshot.fontScale == 1.3)
        #expect(snapshot.animationScale == 0.5)
        #expect(snapshot.autoRotate == false)
        #expect(snapshot.rotation == .landscapeLeft)
        #expect(snapshot.wifi == true)
        #expect(snapshot.mobileData == nil)  // null stays unknown for real toggles
        #expect(snapshot.stayAwake == true)
        #expect(snapshot.pointerLocation == true)
        #expect(snapshot.colorCorrection == .deuteranomaly)
        #expect(snapshot.mediaVolume == 7 && snapshot.mediaVolumeMax == 15)
        #expect(snapshot.locale == "en-US")  // falls back to the product locale
        #expect(snapshot.timeZone == "Asia/Ho_Chi_Minh")
    }

    @Test("unset developer toggles read as off, not unknown")
    func defaults() {
        let snapshot = DeviceSettingsSnapshot.parse(Self.sample)
        #expect(snapshot.showTouches == false)
        #expect(snapshot.colorInversion == false)
        #expect(snapshot.doNotKeepActivities == false)
    }

    @Test("night mode text variants")
    func night() {
        #expect(DeviceSettingsSnapshot.parse("N:Night mode: no").appearance == .light)
        #expect(DeviceSettingsSnapshot.parse("N:Night mode: auto").appearance == .auto)
        #expect(DeviceSettingsSnapshot.parse("").appearance == nil)
    }
}

@Suite("app parsing")
struct AppParsingTests {
    @Test("base64 paths that contain '=' split on the last '='")
    func packageList() {
        let text = """
            package:/data/app/~~Zm9v==/com.example.app-YmFy==/base.apk=com.example.app versionCode:42
            package:/system/app/Foo/Foo.apk=com.android.foo
            garbage line
            """
        let apps = AppParsing.parsePackageList(text, isSystem: false)
        #expect(apps.count == 2)
        #expect(apps[0].packageName == "com.example.app")
        #expect(apps[0].apkPath == "/data/app/~~Zm9v==/com.example.app-YmFy==/base.apk")
        #expect(apps[0].versionCode == 42)
        #expect(apps[1].versionCode == nil)
    }

    static let dump = """
        Activity Resolver Table:
          noise
        Packages:
          Package [com.example.app] (abc123):
            userId=10123
            codePath=/data/app/~~xyz==/com.example.app-abc==
            versionCode=42 minSdk=24 targetSdk=34
            versionName=1.2.3
            flags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA ]
            dataDir=/data/user/0/com.example.app
            firstInstallTime=2024-05-01 10:00:00
            lastUpdateTime=2024-05-02 11:00:00
            installerPackageName=com.android.vending
            declared permissions:
              com.example.app.permission.X: prot=signature
            requested permissions:
              android.permission.INTERNET
              android.permission.CAMERA
            install permissions:
              android.permission.INTERNET: granted=true
            User 0: ceDataInode=1234 installed=true hidden=false suspended=false
              runtime permissions:
                android.permission.CAMERA: granted=false, flags=[ USER_SET ]
          Package [com.other] (def):
            versionName=9.9
        Shared users:
          nothing
        """

    @Test("dumpsys package → details with install and runtime permissions")
    func details() throws {
        let details = try #require(AppParsing.parseDetails(package: "com.example.app", dumpsys: Self.dump))
        #expect(details.versionCode == 42 && details.minSdk == 24 && details.targetSdk == 34)
        #expect(details.versionName == "1.2.3")
        #expect(details.isDebuggable)
        #expect(details.installer == "com.android.vending")
        #expect(details.userId == 10123)
        #expect(details.dataDirectory == "/data/user/0/com.example.app")

        let internet = try #require(details.permissions.first { $0.name == "android.permission.INTERNET" })
        #expect(internet.granted == true && !internet.isRuntime)
        let camera = try #require(details.permissions.first { $0.name == "android.permission.CAMERA" })
        #expect(camera.granted == false && camera.isRuntime)
        #expect(details.permissions.count == 2)  // declared permissions are not requested ones
    }

    @Test("parsing stops at the next package and unknown packages return nil")
    func boundaries() {
        let other = AppParsing.parseDetails(package: "com.other", dumpsys: Self.dump)
        #expect(other?.versionName == "9.9")
        #expect(other?.isDebuggable == false)
        #expect(AppParsing.parseDetails(package: "com.missing", dumpsys: Self.dump) == nil)
    }

    @Test("pm install output")
    func installOutput() {
        #expect(AppParsing.installFailure(from: "Performing Streamed Install\nSuccess\n") == nil)
        #expect(AppParsing.installFailure(from: "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]\n") == "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]")
    }

    @Test("toybox ls -la output becomes file entries")
    func lsLong() {
        let text = """
            total 8
            drwxrwx--x  4 u0_a123 u0_a123 4096 2024-05-01 10:00 .
            drwx------ 20 u0_a123 u0_a123 4096 2024-05-01 10:00 ..
            -rw-rw----  1 u0_a123 u0_a123  512 2024-05-02 11:30 prefs.xml
            drwxrwx--x  2 u0_a123 u0_a123 4096 2024-05-02 11:31 cache dir
            lrwxrwxrwx  1 u0_a123 u0_a123    9 2024-05-02 11:31 link -> target
            """
        let entries = AdbClient.parseLsLong(text)
        #expect(entries.map(\.name) == ["prefs.xml", "cache dir", "link"])
        #expect(entries[0].isRegularFile && entries[0].size == 512)
        #expect(entries[1].isDirectory)
        #expect(entries[2].isSymlink)
        #expect(entries[0].permissionString == "-rw-rw----")
    }
}

@Suite("logcat parsing")
struct LogParserTests {
    @Test("threadtime lines")
    func threadtime() throws {
        let entry = try #require(LogParser.parse(line: "10-14 04:11:52.123  1234  5678 I ActivityManager: Start proc com.foo", id: 1))
        #expect(entry.pid == 1234 && entry.tid == 5678 && entry.level == .info)
        #expect(entry.tag == "ActivityManager")
        #expect(entry.message == "Start proc com.foo")
        #expect(entry.timestamp == "10-14 04:11:52.123")
    }

    @Test("colons inside the message are preserved; a tag with spaces is kept")
    func colons() throws {
        let entry = try #require(LogParser.parse(line: "10-14 04:11:52.123  1  2 E My Tag: error: code=5: fatal", id: 2))
        #expect(entry.tag == "My Tag")
        #expect(entry.message == "error: code=5: fatal")
    }

    @Test("non-log lines are rejected")
    func rejects() {
        #expect(LogParser.parse(line: "--------- beginning of main", id: 3) == nil)
        #expect(LogParser.parse(line: "", id: 4) == nil)
    }

    @Test("filters combine level, text, tag and pid")
    func filtering() throws {
        let entry = try #require(LogParser.parse(line: "10-14 04:11:52.123  10  20 W Net: socket closed", id: 5))
        #expect(LogFilter(minimumLevel: .warning).matches(entry))
        #expect(!LogFilter(minimumLevel: .error).matches(entry))
        #expect(LogFilter(text: "SOCKET").matches(entry))
        #expect(LogFilter(tag: "net").matches(entry))
        #expect(!LogFilter(pid: 11).matches(entry))
        #expect(LogLevel.error > LogLevel.warning)
    }
}

@Suite("host service parsing")
struct HostParsingTests {
    @Test("mdns services")
    func mdns() {
        let text = "adb-ABC-xyz\t_adb-tls-connect._tcp.\t192.168.1.20:37099\nadb-ABC\t_adb-tls-pairing._tcp.\t192.168.1.20:41000\n"
        let services = AdbClient.parseMdns(text)
        #expect(services.map(\.kind) == [.connect, .pairing])
        #expect(services[1].address == "192.168.1.20:41000")
    }

    @Test("wifi address from `ip addr` and from `ip route`")
    func wifi() {
        #expect(AdbClient.parseWifiAddress("    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0") == "192.168.1.42")
        #expect(AdbClient.parseWifiAddress("192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.77") == "192.168.1.77")
        #expect(AdbClient.parseWifiAddress("nothing useful") == nil)
    }

    @Test("adb FAIL messages map to typed errors")
    func failures() {
        #expect(AdbClient.failure("device unauthorized.\nThis adb server's $ADB_VENDOR_KEYS", serial: "S") == .deviceUnauthorized(serial: "S"))
        #expect(AdbClient.failure("device offline", serial: "S") == .deviceOffline(serial: "S"))
        #expect(AdbClient.failure("device 'S' not found", serial: "S") == .deviceNotFound("S"))
        #expect(AdbClient.failure("closed", serial: nil) == .adbFailure("closed"))
    }
}

@Suite("device selection tiers")
struct DeviceSelectionTests {
    let devices = [
        Device(serial: "a1b2c3d4", state: .device, connection: .usb, model: "MI_8"),
        Device(serial: "a1b9zzzz", state: .unauthorized, connection: .usb, usbVendorName: "Xiaomi", usbProductName: "Mi 9"),
        Device(serial: "emulator-5554", state: .device, connection: .emulator, model: "sdk_gphone"),
    ]

    @Test("exact, case-insensitive name, then prefix")
    func tiers() throws {
        #expect(try DeviceSelector.resolve("a1b2c3d4", among: devices).serial == "a1b2c3d4")
        #expect(try DeviceSelector.resolve("mi 8", among: devices).serial == "a1b2c3d4")
        #expect(try DeviceSelector.resolve("A1B2", among: devices).serial == "a1b2c3d4")
        #expect(try DeviceSelector.resolve("emu", among: devices).serial == "emulator-5554")
    }

    @Test("ambiguity lists the candidates instead of guessing")
    func ambiguous() {
        #expect(throws: AdbError.self) { try DeviceSelector.resolve("a1b", among: devices) }
        do { _ = try DeviceSelector.resolve("a1b", among: devices) } catch let AdbError.ambiguousDevice(_, candidates) {
            #expect(candidates.count == 2)
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test("no query: a lone device is chosen, several are refused")
    func implicit() throws {
        #expect(try DeviceSelector.resolve(nil, among: [devices[0]]).serial == "a1b2c3d4")
        #expect(throws: AdbError.self) { try DeviceSelector.resolve(nil, among: devices) }
        #expect(throws: AdbError.self) { try DeviceSelector.resolve("  ", among: devices) }
        #expect(throws: AdbError.self) { try DeviceSelector.resolve("zzz", among: devices) }
    }
}

@Suite("remote file entries")
struct RemoteFileTests {
    @Test("mode bits drive kind and permission string")
    func modes() {
        let directory = RemoteFileEntry(name: "d", mode: 0o040755, size: 0, modified: Date())
        #expect(directory.isDirectory && directory.permissionString == "drwxr-xr-x")
        let file = RemoteFileEntry(name: "f", mode: 0o100644, size: 3, modified: Date())
        #expect(file.isRegularFile && file.permissionString == "-rw-r--r--")
        let link = RemoteFileEntry(name: "l", mode: 0o120777, size: 1, modified: Date())
        #expect(link.isSymlink && link.permissionString == "lrwxrwxrwx")
    }
}

@Suite("review fixes")
struct ReviewFixTests {
    @Test("runtime permissions come from user 0 only")
    func permissionsUserZero() throws {
        let dump = """
            Packages:
              Package [com.example.app] (abc):
                userId=10123
                versionCode=1 minSdk=21 targetSdk=34
                requested permissions:
                  android.permission.CAMERA
                User 0: ceDataInode=1 installed=true
                  runtime permissions:
                    android.permission.CAMERA: granted=true, flags=[ USER_SET ]
                User 999: ceDataInode=2 installed=true
                  runtime permissions:
                    android.permission.CAMERA: granted=false, flags=[ ]
            Shared users:
            """
        let details = try #require(AppParsing.parseDetails(package: "com.example.app", dumpsys: dump))
        #expect(details.permissions.first?.granted == true)
    }

    @Test("emulator console tokens cannot smuggle a second command")
    func consoleInjection() {
        #expect(SettingChange.emulatorNetworkSpeed("edge\nkill").emulatorConsole == ["network speed edgekill"])
        #expect(SettingChange.emulatorNetworkDelay("gsm").emulatorConsole == ["network delay gsm"])
    }

    @Test("airplane mode no longer relies on a protected broadcast")
    func airplane() {
        #expect(!SettingChange.airplaneMode(true).commands[0].contains("AIRPLANE_MODE"))
    }

    @Test("a name that exists is made unique, keeping the extension")
    func uniqueNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("adbhub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("photo.jpg")
        #expect(file.uniqueIfExists(policy: .uniquify) == file)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(file.uniqueIfExists(policy: .overwrite) == file)
        #expect(file.uniqueIfExists(policy: .uniquify).lastPathComponent == "photo 2.jpg")
        FileManager.default.createFile(atPath: directory.appendingPathComponent("photo 2.jpg").path, contents: Data())
        #expect(file.uniqueIfExists(policy: .uniquify).lastPathComponent == "photo 3.jpg")
    }
}

@Suite("conflict policy")
struct ConflictPolicyTests {
    @Test(".refuse throws only when the destination exists")
    func refuse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("adbhub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.bin")
        #expect(try file.resolved(policy: .refuse) == file)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(throws: AdbError.self) { try file.resolved(policy: .refuse) }
        #expect(try file.resolved(policy: .overwrite) == file)
        #expect(try file.resolved(policy: .uniquify).lastPathComponent == "a 2.bin")
    }

    @Test("protected device paths cannot be deleted")
    func protectedPaths() {
        let client = AdbClient()
        for path in ["/", "/sdcard", "/sdcard/", "/storage/emulated/0", "/data", "/system", ""] {
            #expect(throws: AdbError.self) { try client.deleteFile(serial: "unused", path: path) }
        }
    }
}
