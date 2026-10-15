import AdbKit
import Foundation

struct Context {
    let args: Arguments
    let rest: [String]
    let client = AdbClient()

    func device() throws -> Device {
        try DeviceSelector.resolve(args.option("--device", "-d"), among: try client.devices())
    }

    func serial() throws -> String { try device().serial }

    func positional(_ index: Int, _ name: String) throws -> String {
        guard index < rest.count else { throw CLIError.missingArgument(name) }
        return rest[index]
    }

    func int(_ index: Int, _ name: String) throws -> Int {
        let text = try positional(index, name)
        guard let value = Int(text) else { throw CLIError.invalidValue(name, text) }
        return value
    }
}

struct Command {
    let path: [String]
    let usage: String
    let summary: String
    var detail: String = ""
    let run: (Context) async throws -> CommandOutput
}

nonisolated(unsafe) var registry: [Command] = []

func register(_ path: String, _ usage: String, _ summary: String, detail: String = "", run: @escaping (Context) async throws -> CommandOutput) {
    registry.append(Command(path: path.split(separator: " ").map(String.init), usage: usage, summary: summary, detail: detail, run: run))
}

func register(_ path: String, _ summary: String, run: @escaping (Context) async throws -> CommandOutput) {
    register(path, "", summary, run: run)
}

func printUsage() {
    print(
        """
        adbctl — quản lý thiết bị Android từ dòng lệnh, theo phong cách `devicectl` của Apple.

        Tuỳ chọn chung:
          -d, --device <serial|tên>     Thiết bị cần thao tác (bỏ qua nếu chỉ có 1 thiết bị)
          --json-output <đường dẫn|->   Ghi kết quả JSON có version ra file ('-' = stdout)
          -h, --help                    Hiện trợ giúp (kèm lệnh để xem chi tiết lệnh đó)

        Lệnh:
        """)
    var lastGroup = ""
    for command in registry {
        let group = command.path[0]
        if group != lastGroup, !lastGroup.isEmpty { print("") }
        lastGroup = group
        let signature = command.path.joined(separator: " ") + (command.usage.isEmpty ? "" : " " + command.usage)
        // Long signatures put the summary on its own line so columns never blow out.
        if signature.count <= 58 {
            print("  " + pad(signature, 60) + String(command.summary.prefix(90)))
        } else {
            print("  " + signature)
            print("  " + String(repeating: " ", count: 60) + String(command.summary.prefix(90)))
        }
    }
}
