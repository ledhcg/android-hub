import Testing

@testable import AdbKit

@Suite("devices -l parsing")
struct DeviceListParserTests {
    @Test("unauthorized USB phone has no model, only a bus path")
    func unauthorizedUSB() throws {
        let devices = DeviceListParser.parse("c2f55a15               unauthorized usb:0-1 transport_id:1\n")
        let device = try #require(devices.first)
        #expect(devices.count == 1)
        #expect(device.serial == "c2f55a15")
        #expect(device.state == .unauthorized)
        #expect(device.connection == .usb)
        #expect(device.usbPath == "0-1")
        #expect(device.transportId == 1)
        #expect(device.model == nil)
        #expect(device.displayName == "c2f55a15")
    }

    @Test("emulator and wireless devices")
    func emulatorAndNetwork() {
        let text = """
            emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:2
            192.168.1.20:5555      device product:starqltek model:SM_G960N device:starqltek transport_id:3

            """
        let devices = DeviceListParser.parse(text)
        #expect(devices.map(\.connection) == [.emulator, .network])
        #expect(devices[0].isReady)
        #expect(devices[1].displayName == "SM G960N")
        #expect(devices[1].codename == "starqltek")
    }

    @Test("`no permissions` spans two tokens and keeps the following properties")
    func noPermissions() throws {
        let line = "0123456789ABCDEF no permissions [udev rules] usb:1-2 transport_id:7"
        let device = try #require(DeviceListParser.parseLine(line))
        #expect(device.state == .noPermissions)
        #expect(device.usbPath == "1-2")
    }

    @Test("empty input and unknown states")
    func edgeCases() throws {
        #expect(DeviceListParser.parse("").isEmpty)
        let device = try #require(DeviceListParser.parseLine("abc weird-state usb:1-1"))
        #expect(device.state == .unknown("weird-state"))
    }

    @Test("USB registry names are used when adb has no model")
    func usbFallbackName() {
        var device = Device(serial: "c2f55a15", state: .unauthorized, connection: .usb)
        device.usbVendorName = "Xiaomi"
        device.usbProductName = "Xiaomi MI 8"
        #expect(device.displayName == "Xiaomi MI 8")  // vendor already inside product name
        device.usbProductName = "MI 8"
        #expect(device.displayName == "Xiaomi MI 8")
    }
}

@Suite("device info parsing")
struct DeviceInfoParserTests {
    static let sample = """
        [ro.product.manufacturer]: [Xiaomi]
        [ro.product.model]: [MI 8]
        [ro.product.device]: [dipper]
        [ro.build.version.release]: [10]
        [ro.build.version.sdk]: [29]
        [ro.build.version.security_patch]: [2020-09-01]
        [ro.product.cpu.abi]: [arm64-v8a]
        [ro.hardware]: [qcom]
        @@ADBHUB@@wm
        Physical size: 1080x2248
        Override size: 720x1500
        Physical density: 440
        @@ADBHUB@@battery
        Current Battery Service state:
          AC powered: false
          USB powered: true
          Wireless powered: false
          status: 2
          level: 87
          temperature: 285
        """

    @Test("props, display and battery are extracted")
    func parsesSample() throws {
        let info = DeviceInfoDetails.parse(output: Self.sample, serial: "c2f55a15")
        #expect(info.manufacturer == "Xiaomi")
        #expect(info.model == "MI 8")
        #expect(info.sdkInt == 29)
        #expect(info.isEmulator == false)
        #expect(info.physicalSize == .init(width: 1080, height: 2248))
        #expect(info.overrideSize == .init(width: 720, height: 1500))
        #expect(info.physicalDensity == 440)
        #expect(info.overrideDensity == nil)

        let battery = try #require(info.battery)
        #expect(battery.level == 87)
        #expect(battery.isCharging == true)
        #expect(battery.poweredBy == ["usb"])
        #expect(battery.temperatureCelsius == 28.5)
    }

    @Test("emulators are recognised by hardware name")
    func emulatorDetection() {
        let info = DeviceInfoDetails.parse(output: "[ro.hardware]: [ranchu]\n", serial: "somename")
        #expect(info.isEmulator)
    }

    @Test("getprop values containing brackets survive")
    func bracketValues() {
        let props = DeviceInfoDetails.parseGetprop(["[ro.x]: [a [b] c]"])
        #expect(props["ro.x"] == "a [b] c")
    }
}

@Suite("device selection")
struct DeviceSelectorTests {
    let devices = [
        Device(serial: "AAA", state: .device, connection: .usb),
        Device(serial: "BBB", state: .unauthorized, connection: .usb),
    ]

    @Test("exact serial resolves")
    func exact() throws {
        #expect(try DeviceSelector.resolve("BBB", among: devices).serial == "BBB")
    }

    @Test("unknown serial throws deviceNotFound")
    func missing() {
        #expect(throws: AdbError.deviceNotFound("ZZZ")) {
            try DeviceSelector.resolve("ZZZ", among: devices)
        }
    }
}
