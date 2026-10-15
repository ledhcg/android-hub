import AdbKit
import Foundation

func registerDeviceCommands() {
    register("list devices", "Liệt kê thiết bị đang kết nối") { context in
        let devices = try context.client.devices()
        return CommandOutput(json: ["devices": devices]) {
            guard !devices.isEmpty else { return print("Không có thiết bị nào được kết nối.") }
            printTable(
                ["Tên", "Serial", "Trạng thái", "Kết nối"],
                devices.map { [$0.displayName, $0.serial, $0.state.rawValue, $0.connection.rawValue] })
            let unauthorized = devices.filter { $0.state == .unauthorized }
            if !unauthorized.isEmpty {
                print("\n\(unauthorized.count) thiết bị chưa được cấp quyền: mở khoá điện thoại và bấm Allow ở hộp thoại USB debugging.")
            }
        }
    }

    register("watch devices", "Theo dõi thiết bị cắm/rút/đổi trạng thái (Ctrl-C để thoát)") { context in
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for try await devices in context.client.trackDevices() {
            print("[\(formatter.string(from: Date()))] \(devices.count) thiết bị")
            if !devices.isEmpty {
                printTable(["Tên", "Serial", "Trạng thái", "Kết nối"], devices.map { [$0.displayName, $0.serial, $0.state.rawValue, $0.connection.rawValue] })
            }
            print("")
        }
        return CommandOutput()
    }

    register("manage discover", "Tìm thiết bị Wireless debugging trên mạng LAN (mDNS)") { context in
        let services = try context.client.discoverWirelessServices()
        return CommandOutput(json: ["services": services]) {
            guard !services.isEmpty else { return print("Không thấy dịch vụ nào. Bật 'Wireless debugging' trên điện thoại (Android 11+).") }
            printTable(["Tên", "Loại", "Địa chỉ"], services.map { [$0.name, $0.kind.rawValue, $0.address] })
        }
    }

    register("manage pair", "--address <ip:port> --code <6 số>", "Ghép đôi không dây (Android 11+: 'Pair device with pairing code')") { context in
        guard let address = context.args.option("--address"), let code = context.args.option("--code") else {
            throw CLIError.missingArgument("--address và --code")
        }
        let message = try context.client.pair(address: address, code: code)
        return CommandOutput(json: ["message": message]) { print(message) }
    }

    register("manage connect", "--address <ip[:port]>", "Kết nối thiết bị qua mạng") { context in
        guard let address = context.args.option("--address") else { throw CLIError.missingArgument("--address") }
        let message = try context.client.connect(address: address)
        return CommandOutput(json: ["message": message]) { print(message) }
    }

    register("manage disconnect", "[--address <ip:port>]", "Ngắt kết nối thiết bị mạng (bỏ --address = ngắt tất cả)") { context in
        try context.client.disconnect(address: context.args.option("--address"))
        return CommandOutput(json: ["disconnected": context.args.option("--address") ?? "all"]) { print("Đã ngắt kết nối.") }
    }

    register("manage tcpip", "--device <id> [--port 5555]", "Chuyển adbd sang chế độ TCP/IP (máy Android < 11 cần bước này qua USB)") { context in
        let serial = try context.serial()
        let port = try context.args.intOption("--port", default: 5555) ?? 5555
        let reply = try context.client.enableTCPIP(serial: serial, port: port)
        let address = try? context.client.wifiAddress(serial: serial)
        return CommandOutput(json: ["message": reply, "address": address.map { "\($0):\(port)" } ?? ""]) {
            print(reply)
            if let address { print("Kết nối bằng: adbctl manage connect --address \(address):\(port)") }
        }
    }

    register("device info details", "Thông tin chi tiết thiết bị") { context in
        let serial = try context.serial()
        let info = try context.client.deviceInfo(serial: serial)
        return CommandOutput(json: info) {
            func line(_ label: String, _ value: String?) {
                if let value, !value.isEmpty { print(pad(label, 22) + value) }
            }
            func size(_ s: DeviceInfoDetails.Size?) -> String? { s.map { "\($0.width)x\($0.height)" } }
            line("Serial", info.serial)
            line("Nhà sản xuất", info.manufacturer)
            line("Model", info.model)
            line("Tên thương mại", info.marketName)
            line("Codename", info.codename)
            line("Android", info.androidVersion.map { v in info.sdkInt.map { "\(v) (SDK \($0))" } ?? v })
            line("Bản vá bảo mật", info.securityPatch)
            line("Bản build", info.buildId)
            line("ABI", info.primaryABI)
            line("Loại", info.isEmulator ? "Emulator" : "Máy thật")
            line("Màn hình", size(info.physicalSize))
            line("Màn hình (override)", size(info.overrideSize))
            line("Density", info.physicalDensity.map(String.init))
            line("Density (override)", info.overrideDensity.map(String.init))
            if let battery = info.battery {
                let sources = battery.poweredBy.isEmpty ? "" : " [\(battery.poweredBy.joined(separator: ", "))]"
                line("Pin", (battery.level.map { "\($0)%" } ?? "?") + (battery.isCharging == true ? ", đang sạc" : "") + sources)
                line("Nhiệt độ pin", battery.temperatureCelsius.map { String(format: "%.1f°C", $0) })
            }
        }
    }

    register("device props", "Toàn bộ system properties (getprop)") { context in
        let properties = try context.client.properties(serial: try context.serial())
        return CommandOutput(json: properties) {
            for key in properties.keys.sorted() { print("\(key) = \(properties[key]!)") }
        }
    }
}
