import AdbKit
import Foundation

func registerDeviceCommands() {
    register("list devices", "List connected devices") { context in
        let devices = try context.client.devices()
        return CommandOutput(json: ["devices": devices]) {
            guard !devices.isEmpty else { return print("No devices connected.") }
            printTable(
                ["Name", "Serial", "State", "Connection"],
                devices.map { [$0.displayName, $0.serial, $0.state.rawValue, $0.connection.rawValue] })
            let unauthorized = devices.filter { $0.state == .unauthorized }
            if !unauthorized.isEmpty {
                print("\n\(unauthorized.count) device(s) not authorized: unlock the phone and tap Allow in the USB debugging dialog.")
            }
        }
    }

    register("watch devices", "Watch devices being plugged in, unplugged or changing state (Ctrl-C to exit)") { context in
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for try await devices in context.client.trackDevices() {
            print("[\(formatter.string(from: Date()))] \(devices.count) device(s)")
            if !devices.isEmpty {
                printTable(["Name", "Serial", "State", "Connection"], devices.map { [$0.displayName, $0.serial, $0.state.rawValue, $0.connection.rawValue] })
            }
            print("")
        }
        return CommandOutput()
    }

    register("manage discover", "Discover Wireless debugging devices on the local network (mDNS)") { context in
        let services = try context.client.discoverWirelessServices()
        return CommandOutput(json: ["services": services]) {
            guard !services.isEmpty else { return print("No services found. Enable 'Wireless debugging' on the phone (Android 11+).") }
            printTable(["Name", "Type", "Address"], services.map { [$0.name, $0.kind.rawValue, $0.address] })
        }
    }

    register("manage pair", "--address <ip:port> --code <6 digits>", "Pair over Wi-Fi (Android 11+: 'Pair device with pairing code')") { context in
        guard let address = context.args.option("--address"), let code = context.args.option("--code") else {
            throw CLIError.missingArgument("--address and --code")
        }
        let message = try context.client.pair(address: address, code: code)
        return CommandOutput(json: ["message": message]) { print(message) }
    }

    register("manage connect", "--address <ip[:port]>", "Connect to a device over the network") { context in
        guard let address = context.args.option("--address") else { throw CLIError.missingArgument("--address") }
        let message = try context.client.connect(address: address)
        return CommandOutput(json: ["message": message]) { print(message) }
    }

    register("manage disconnect", "[--address <ip:port>]", "Disconnect network devices (omit --address to disconnect all)") { context in
        try context.client.disconnect(address: context.args.option("--address"))
        return CommandOutput(json: ["disconnected": context.args.option("--address") ?? "all"]) { print("Disconnected.") }
    }

    register("manage tcpip", "--device <id> [--port 5555]", "Switch adbd to TCP/IP mode (devices before Android 11 need this step over USB)") { context in
        let serial = try context.serial()
        let port = try context.args.intOption("--port", default: 5555) ?? 5555
        let reply = try context.client.enableTCPIP(serial: serial, port: port)
        let address = try? context.client.wifiAddress(serial: serial)
        return CommandOutput(json: ["message": reply, "address": address.map { "\($0):\(port)" } ?? ""]) {
            print(reply)
            if let address { print("Connect with: adbctl manage connect --address \(address):\(port)") }
        }
    }

    register("device info details", "Detailed device information") { context in
        let serial = try context.serial()
        let info = try context.client.deviceInfo(serial: serial)
        return CommandOutput(json: info) {
            func line(_ label: String, _ value: String?) {
                if let value, !value.isEmpty { print(pad(label, 22) + value) }
            }
            func size(_ s: DeviceInfoDetails.Size?) -> String? { s.map { "\($0.width)x\($0.height)" } }
            line("Serial", info.serial)
            line("Manufacturer", info.manufacturer)
            line("Model", info.model)
            line("Marketing name", info.marketName)
            line("Codename", info.codename)
            line("Android", info.androidVersion.map { v in info.sdkInt.map { "\(v) (SDK \($0))" } ?? v })
            line("Security patch", info.securityPatch)
            line("Build", info.buildId)
            line("ABI", info.primaryABI)
            line("Type", info.isEmulator ? "Emulator" : "Physical device")
            line("Display", size(info.physicalSize))
            line("Display (override)", size(info.overrideSize))
            line("Density", info.physicalDensity.map(String.init))
            line("Density (override)", info.overrideDensity.map(String.init))
            if let battery = info.battery {
                let sources = battery.poweredBy.isEmpty ? "" : " [\(battery.poweredBy.joined(separator: ", "))]"
                line("Battery", (battery.level.map { "\($0)%" } ?? "?") + (battery.isCharging == true ? ", charging" : "") + sources)
                line("Battery temperature", battery.temperatureCelsius.map { String(format: "%.1f°C", $0) })
            }
        }
    }

    register("device props", "All system properties (getprop)") { context in
        let properties = try context.client.properties(serial: try context.serial())
        return CommandOutput(json: properties) {
            for key in properties.keys.sorted() { print("\(key) = \(properties[key]!)") }
        }
    }
}
