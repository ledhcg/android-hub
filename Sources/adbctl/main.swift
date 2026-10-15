import AdbKit
import Foundation

// adbctl — a `devicectl`-style command line for Android devices.
// Scripts should read `--json-output` (versioned), never the human-readable text.

registerDeviceCommands()
registerSettingsCommands()
registerAppCommands()
registerFileCommands()
registerDiagnosticCommands()
registerMediaCommands()
registerEmulatorCommands()

func runCLI() async throws {
    // stdout is fully buffered when piped or redirected; `watch` and `logs` must show lines immediately.
    setvbuf(stdout, nil, _IOLBF, 0)

    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    if arguments.words.isEmpty || arguments.words == ["help"] || (arguments.has("--help", "-h") && arguments.words.isEmpty) {
        printUsage()
        return
    }

    // Longest matching command path wins ("device apps container list" over "device apps").
    let matches = registry.filter { arguments.words.starts(with: $0.path) }
    guard let command = matches.max(by: { $0.path.count < $1.path.count }) else {
        throw CLIError.unknownCommand(arguments.words)
    }
    if arguments.has("--help", "-h") {
        print("adbctl \(command.path.joined(separator: " ")) \(command.usage)\n  \(command.summary)")
        if !command.detail.isEmpty { print("\n\(command.detail)") }
        return
    }

    let context = Context(args: arguments, rest: Array(arguments.words.dropFirst(command.path.count)))
    let name = command.path.joined(separator: " ")
    let jsonPath = arguments.option("--json-output")

    do {
        let output = try await command.run(context)
        if let jsonPath {
            try writeJSON(Envelope(info: .init(command: name, outcome: "succeeded"), result: output.json, error: nil), to: jsonPath)
            if jsonPath == "-" { return }
        }
        output.human()
    } catch {
        if let jsonPath {
            try? writeJSON(Envelope(info: .init(command: name, outcome: "failed"), result: nil, error: .init(message: "\(error)")), to: jsonPath)
        }
        throw error
    }
}

do {
    try await runCLI()
} catch {
    FileHandle.standardError.write(Data("Lỗi: \(error)\n".utf8))
    exit(1)
}
