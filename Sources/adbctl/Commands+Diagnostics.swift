import AdbKit
import Foundation

func registerDiagnosticCommands() {
    register("device logs", "[--level W] [--filter text] [--tag t] [--count N] [--no-backlog]", "Xem logcat theo thời gian thực") { context in
        let serial = try context.serial()
        let levelText = context.args.option("--level") ?? "V"
        guard let level = levelText.first.flatMap({ LogLevel(rawValue: Character(String($0).uppercased())) }) else {
            throw CLIError.invalidValue("--level", levelText)
        }
        let filter = LogFilter(minimumLevel: level, text: context.args.option("--filter") ?? "", tag: context.args.option("--tag") ?? "")
        let count = try context.args.intOption("--count")
        let backlog = context.args.has("--no-backlog") ? 0 : 200
        var shown = 0
        var collected: [LogEntry] = []
        for try await entry in try context.client.logStream(serial: serial, backlog: backlog) where filter.matches(entry) {
            if context.args.option("--json-output") != nil { collected.append(entry) } else {
                print("\(entry.timestamp) \(entry.level.rawValue) \(entry.tag): \(entry.message)")
            }
            shown += 1
            if let count, shown >= count { break }
        }
        return CommandOutput(json: ["entries": collected]) {}
    }

    register("device logs clear", "Xoá bộ đệm logcat") { context in
        try context.client.clearLog(serial: try context.serial())
        return CommandOutput(json: ["cleared": true]) { print("Đã xoá logcat.") }
    }

    register("device crashes", "[--tag app-crash|app-anr|native|system-app|system-server|strictmode]", "Xem crash/ANR gần đây (dropbox)") { context in
        let names: [String: DropBoxTag] = [
            "app-crash": .appCrash, "app-anr": .appANR, "native": .appNativeCrash, "system-app": .systemAppCrash,
            "system-server": .systemServerCrash, "strictmode": .strictMode,
        ]
        let key = context.args.option("--tag") ?? "app-crash"
        guard let tag = names[key] else { throw CLIError.invalidValue("--tag", key) }
        let text = try context.client.dropBox(serial: try context.serial(), tag: tag)
        return CommandOutput(json: ["tag": tag.rawValue, "text": text]) { print(text.isEmpty ? "(không có)" : text) }
    }

    register("device services", "Danh sách system service (cho dumpsys)") { context in
        let services = try context.client.systemServices(serial: try context.serial())
        return CommandOutput(json: ["services": services]) { services.forEach { print($0) } }
    }

    register("device dumpsys", "[service]", "dumpsys toàn bộ hoặc một service") { context in
        let text = try context.client.dumpsys(serial: try context.serial(), service: context.rest.first)
        return CommandOutput(json: ["text": text]) { print(text) }
    }

    register("device diagnostics collect", "--output <thư mục> [--bugreport]", "Thu thập getprop, logcat, dumpsys, crash, screenshot (+ bugreport)") { context in
        let directory = expandPath(context.args.option("--output", "-o") ?? ".")
        let folder = try await context.client.collectDiagnostics(
            serial: try context.serial(), to: directory, includeBugReport: context.args.has("--bugreport")
        ) { step in FileHandle.standardError.write(Data("… \(step)\n".utf8)) }
        return CommandOutput(json: ["folder": folder.path]) { print(folder.path) }
    }

    register("device bugreport", "--output <thư mục>", "Chạy bugreport đầy đủ và tải file zip về") { context in
        let directory = expandPath(context.args.option("--output", "-o") ?? ".")
        let file = try await context.client.bugReport(serial: try context.serial(), to: directory) { percent in
            FileHandle.standardError.write(Data("\rbugreport \(percent)%".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        return CommandOutput(json: ["file": file.path]) { print(file.path) }
    }
}
