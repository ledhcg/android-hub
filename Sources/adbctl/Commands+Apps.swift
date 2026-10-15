import AdbKit
import Foundation

func registerAppCommands() {
    register("device apps list", "[--system] [--filter <text>]", "Liệt kê app đã cài (mặc định chỉ app người dùng)") { context in
        var apps = try context.client.installedApps(serial: try context.serial())
        if !context.args.has("--system") { apps = apps.filter { !$0.isSystem } }
        if let filter = context.args.option("--filter")?.lowercased() { apps = apps.filter { $0.packageName.lowercased().contains(filter) } }
        return CommandOutput(json: ["apps": apps]) {
            guard !apps.isEmpty else { return print("Không có app nào.") }
            printTable(["Package", "Version code", "Loại"], apps.map { [$0.packageName, $0.versionCode.map(String.init) ?? "-", $0.isSystem ? "system" : "user"] })
        }
    }

    register("device apps info", "<package>", "Chi tiết app: phiên bản, quyền, debuggable...") { context in
        let package = try context.positional(0, "package")
        let details = try context.client.appDetails(serial: try context.serial(), package: package)
        return CommandOutput(json: details) {
            func line(_ label: String, _ value: String?) { if let value, !value.isEmpty { print(pad(label, 20) + value) } }
            line("Package", details.packageName)
            line("Phiên bản", [details.versionName, details.versionCode.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
            line("minSdk / targetSdk", "\(details.minSdk.map(String.init) ?? "?") / \(details.targetSdk.map(String.init) ?? "?")")
            line("Cài lần đầu", details.firstInstall)
            line("Cập nhật", details.lastUpdate)
            line("Nguồn cài", details.installer)
            line("User ID", details.userId.map(String.init))
            line("Data dir", details.dataDirectory)
            line("Debuggable", details.isDebuggable ? "có" : "không")
            line("System", details.isSystem ? "có" : "không")
            if !details.permissions.isEmpty {
                print("\nQuyền (\(details.permissions.count)):")
                for permission in details.permissions {
                    let state = permission.granted.map { $0 ? "granted" : "denied" } ?? "-"
                    print("  \(pad(state, 8)) \(permission.isRuntime ? "[runtime] " : "")\(permission.name)")
                }
            }
        }
    }

    register("device apps install", "<file.apk...> [--downgrade] [--grant-all] [--no-replace]", "Cài APK (nhiều file = split APK)") { context in
        guard !context.rest.isEmpty else { throw CLIError.missingArgument("file .apk") }
        let urls = context.rest.map(expandPath)
        let options = InstallOptions(
            replaceExisting: !context.args.has("--no-replace"), allowDowngrade: context.args.has("--downgrade"),
            grantAllPermissions: context.args.has("--grant-all"))
        try context.client.installApps(serial: try context.serial(), apks: urls, options: options) { stage in
            if case .installing = stage { FileHandle.standardError.write(Data("Đang cài...\n".utf8)) }
        }
        return CommandOutput(json: ["installed": urls.map(\.lastPathComponent)]) { print("Cài đặt thành công.") }
    }

    register("device apps uninstall", "<package> [--keep-data]", "Gỡ app") { context in
        let package = try context.positional(0, "package")
        try context.client.uninstallApp(serial: try context.serial(), package: package, keepData: context.args.has("--keep-data"))
        return CommandOutput(json: ["uninstalled": package]) { print("Đã gỡ \(package).") }
    }

    for (verb, summary) in [("launch", "Mở app"), ("stop", "Buộc dừng app"), ("clear", "Xoá dữ liệu app"), ("settings", "Mở trang thông tin app trong Cài đặt")] {
        register("device apps \(verb)", "<package>", summary) { context in
            let package = try context.positional(0, "package")
            let serial = try context.serial()
            switch verb {
            case "launch": try context.client.launchApp(serial: serial, package: package)
            case "stop": try context.client.forceStopApp(serial: serial, package: package)
            case "clear": try context.client.clearAppData(serial: serial, package: package)
            default: try context.client.openAppInfo(serial: serial, package: package)
            }
            return CommandOutput(json: [verb: package]) { print("OK: \(verb) \(package)") }
        }
    }

    for (verb, granted) in [("grant", true), ("revoke", false)] {
        register("device apps \(verb)", "<package> <permission>", granted ? "Cấp quyền runtime" : "Thu hồi quyền runtime") { context in
            let package = try context.positional(0, "package")
            let permission = try context.positional(1, "permission")
            try context.client.setPermission(serial: try context.serial(), package: package, permission: permission, granted: granted)
            return CommandOutput(json: [verb: permission]) { print("OK: \(verb) \(permission)") }
        }
    }

    register("device apps extract", "<package> --output <thư mục> [--force]", "Lấy file APK (base + split) của app về máy Mac") { context in
        let package = try context.positional(0, "package")
        let directory = expandPath(context.args.option("--output", "-o") ?? ".")
        let files = try context.client.extractApks(serial: try context.serial(), package: package, to: directory, conflict: conflictPolicy(context.args))
        return CommandOutput(json: ["files": files.map(\.path)]) { files.forEach { print($0.path) } }
    }

    register("device apps container list", "<package> [path]", "Duyệt data container của app debuggable (run-as)") { context in
        let package = try context.positional(0, "package")
        let path = context.rest.count > 1 ? context.rest[1] : "."
        let entries = try context.client.containerList(serial: try context.serial(), package: package, path: path)
        return CommandOutput(json: ["entries": entries]) {
            printTable(["Quyền", "Kích thước", "Tên"], entries.map { [$0.permissionString, formatBytes($0.size), $0.name] })
        }
    }

    register("device apps container pull", "<package> <path> --output <file> [--force]", "Lấy file từ data container của app debuggable") { context in
        let package = try context.positional(0, "package")
        let path = try context.positional(1, "path")
        let output = expandPath(context.args.option("--output", "-o") ?? (path as NSString).lastPathComponent)
        try context.client.containerPull(serial: try context.serial(), package: package, path: path, to: output, conflict: conflictPolicy(context.args))
        return CommandOutput(json: ["file": output.path]) { print(output.path) }
    }
}
