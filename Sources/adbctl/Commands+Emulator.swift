import AdbKit
import EmulatorKit
import Foundation

func registerEmulatorCommands() {
    register("emulator list", "List AVDs (Android virtual devices)") { _ in
        let manager = try AvdManager.makeDefault()
        let avds = try manager.listAVDs()
        let running = (try? manager.runningEmulators()) ?? [:]
        return CommandOutput(json: obj(("avds", avds), ("running", running))) {
            guard !avds.isEmpty else { return print("No AVDs yet. Create one with: adbctl emulator create") }
            printTable(
                ["Name", "API", "Device", "Display", "Running"],
                avds.map { avd in
                    [
                        avd.name, avd.apiTarget ?? "-", avd.deviceDefinition ?? "-",
                        avd.width.flatMap { w in avd.height.map { "\(w)x\($0)" } } ?? "-",
                        running.first(where: { $0.value == avd.name })?.key ?? "-",
                    ]
                })
        }
    }

    register("emulator images", "List installed system images") { _ in
        let images = try AvdManager.makeDefault().installedSystemImages()
        return CommandOutput(json: ["images": images]) {
            printTable(["Package", "Description"], images.map { [$0.packageId, $0.description ?? ""] })
        }
    }

    register("emulator devices", "List device definitions (pixel_8, pixel_tablet...)") { _ in
        let devices = try AvdManager.makeDefault().deviceDefinitions()
        return CommandOutput(json: ["devices": devices]) { devices.forEach { print($0) } }
    }

    register("emulator create", "--name <name> --hardware <device-id> --image <package-id> [--force]", "Create a new AVD") { context in
        guard let name = context.args.option("--name"), let hardware = context.args.option("--hardware"),
            let image = context.args.option("--image")
        else { throw CLIError.missingArgument("--name, --hardware, --image") }
        let avd = try AvdManager.makeDefault().createAVD(name: name, device: hardware, systemImage: image, force: context.args.has("--force"))
        return CommandOutput(json: avd) { print("Created AVD '\(avd.name)'.") }
    }

    register("emulator delete", "<name>", "Delete an AVD") { context in
        let name = try context.positional(0, "AVD name")
        try AvdManager.makeDefault().deleteAVD(name: name)
        return CommandOutput(json: ["deleted": name]) { print("Deleted '\(name)'.") }
    }

    register("emulator start", "<name> [--headless] [--cold-boot] [--wipe-data] [--wait]", "Start an emulator") { context in
        let name = try context.positional(0, "AVD name")
        let manager = try AvdManager.makeDefault()
        let options = EmulatorLaunchOptions(headless: context.args.has("--headless"), coldBoot: context.args.has("--cold-boot"), wipeData: context.args.has("--wipe-data"))
        let launched = try manager.start(name: name, options: options)
        let pid = launched.processIdentifier
        var serial: String?
        if context.args.has("--wait") {
            FileHandle.standardError.write(Data("Waiting for boot...\n".utf8))
            serial = try await manager.waitUntilBooted(name: name, launched: launched)
        }
        return CommandOutput(json: ["pid": "\(pid)", "serial": serial ?? ""]) {
            print(serial.map { "Booted: \($0)" } ?? "Started (pid \(pid)); use `adbctl list devices` to follow progress.")
        }
    }

    register("emulator stop", "[--device <emulator-serial>]", "Stop an emulator") { context in
        let serial = try context.serial()
        try AvdManager.makeDefault().stop(serial: serial)
        return CommandOutput(json: ["stopped": serial]) { print("Stopped \(serial).") }
    }

    register("emulator wipe", "<name>", "Erase user data of an AVD (must be stopped)") { context in
        let name = try context.positional(0, "AVD name")
        try AvdManager.makeDefault().wipeData(name: name)
        return CommandOutput(json: ["wiped": name]) { print("Erased data of '\(name)'.") }
    }

    register("emulator install-image", "<package-id>", "Download a system image with sdkmanager (licenses must be accepted first)") { context in
        let package = try context.positional(0, "package id")
        try AvdManager.makeDefault().installSystemImage(package)
        return CommandOutput(json: ["installed": package]) { print("Installed \(package).") }
    }
}
