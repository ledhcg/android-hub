import AdbKit
import EmulatorKit
import Foundation

func registerEmulatorCommands() {
    register("emulator list", "Liệt kê các AVD (máy ảo Android)") { _ in
        let manager = try AvdManager.makeDefault()
        let avds = try manager.listAVDs()
        let running = (try? manager.runningEmulators()) ?? [:]
        return CommandOutput(json: obj(("avds", avds), ("running", running))) {
            guard !avds.isEmpty else { return print("Chưa có AVD nào. Tạo bằng: adbctl emulator create") }
            printTable(
                ["Tên", "API", "Thiết bị", "Màn hình", "Đang chạy"],
                avds.map { avd in
                    [
                        avd.name, avd.apiTarget ?? "-", avd.deviceDefinition ?? "-",
                        avd.width.flatMap { w in avd.height.map { "\(w)x\($0)" } } ?? "-",
                        running.first(where: { $0.value == avd.name })?.key ?? "-",
                    ]
                })
        }
    }

    register("emulator images", "Liệt kê system image đã cài") { _ in
        let images = try AvdManager.makeDefault().installedSystemImages()
        return CommandOutput(json: ["images": images]) {
            printTable(["Package", "Mô tả"], images.map { [$0.packageId, $0.description ?? ""] })
        }
    }

    register("emulator devices", "Liệt kê device definition (pixel_8, pixel_tablet...)") { _ in
        let devices = try AvdManager.makeDefault().deviceDefinitions()
        return CommandOutput(json: ["devices": devices]) { devices.forEach { print($0) } }
    }

    register("emulator create", "--name <tên> --hardware <device-id> --image <package-id> [--force]", "Tạo AVD mới") { context in
        guard let name = context.args.option("--name"), let hardware = context.args.option("--hardware"),
            let image = context.args.option("--image")
        else { throw CLIError.missingArgument("--name, --hardware, --image") }
        let avd = try AvdManager.makeDefault().createAVD(name: name, device: hardware, systemImage: image, force: context.args.has("--force"))
        return CommandOutput(json: avd) { print("Đã tạo AVD '\(avd.name)'.") }
    }

    register("emulator delete", "<tên>", "Xoá AVD") { context in
        let name = try context.positional(0, "tên AVD")
        try AvdManager.makeDefault().deleteAVD(name: name)
        return CommandOutput(json: ["deleted": name]) { print("Đã xoá '\(name)'.") }
    }

    register("emulator start", "<tên> [--headless] [--cold-boot] [--wipe-data] [--wait]", "Khởi động emulator") { context in
        let name = try context.positional(0, "tên AVD")
        let manager = try AvdManager.makeDefault()
        let options = EmulatorLaunchOptions(headless: context.args.has("--headless"), coldBoot: context.args.has("--cold-boot"), wipeData: context.args.has("--wipe-data"))
        let launched = try manager.start(name: name, options: options)
        let pid = launched.processIdentifier
        var serial: String?
        if context.args.has("--wait") {
            FileHandle.standardError.write(Data("Đang chờ boot...\n".utf8))
            serial = try await manager.waitUntilBooted(name: name, launched: launched)
        }
        return CommandOutput(json: ["pid": "\(pid)", "serial": serial ?? ""]) {
            print(serial.map { "Đã boot: \($0)" } ?? "Đã khởi động (pid \(pid)); dùng `adbctl list devices` để theo dõi.")
        }
    }

    register("emulator stop", "[--device <emulator-serial>]", "Tắt emulator") { context in
        let serial = try context.serial()
        try AvdManager.makeDefault().stop(serial: serial)
        return CommandOutput(json: ["stopped": serial]) { print("Đã tắt \(serial).") }
    }

    register("emulator wipe", "<tên>", "Xoá dữ liệu người dùng của AVD (đang tắt)") { context in
        let name = try context.positional(0, "tên AVD")
        try AvdManager.makeDefault().wipeData(name: name)
        return CommandOutput(json: ["wiped": name]) { print("Đã xoá dữ liệu '\(name)'.") }
    }

    register("emulator install-image", "<package-id>", "Tải system image bằng sdkmanager (cần chấp nhận license trước)") { context in
        let package = try context.positional(0, "package id")
        try AvdManager.makeDefault().installSystemImage(package)
        return CommandOutput(json: ["installed": package]) { print("Đã cài \(package).") }
    }
}
