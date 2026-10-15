import Foundation

/// Minimal argument parser: positional words, `--name value` / `--name=value` options and boolean flags.
struct Arguments {
    var words: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    /// Options that never take a value.
    static let booleanFlags: Set<String> = [
        "--help", "-h", "--system", "--bugreport", "--headless", "--cold-boot", "--wipe-data", "--force",
        "--keep-data", "--downgrade", "--grant-all", "--no-replace", "--no-backlog", "--clear", "--wait", "--user", "--all",
    ]

    init(_ arguments: [String]) throws {
        var iterator = arguments.makeIterator()
        var optionsEnded = false
        while let argument = iterator.next() {
            if optionsEnded {
                words.append(argument)
            } else if argument == "--" {
                optionsEnded = true  // everything after is literal (e.g. text or coordinates starting with '-')
            } else if Self.looksLikeOption(argument) {
                if let equals = argument.firstIndex(of: "="), argument.hasPrefix("--") {
                    options[String(argument[..<equals])] = String(argument[argument.index(after: equals)...])
                } else if Self.booleanFlags.contains(argument) {
                    flags.insert(argument)
                } else {
                    guard let value = iterator.next() else { throw CLIError.missingValue(argument) }
                    options[argument] = value
                }
            } else {
                words.append(argument)
            }
        }
    }

    /// `-d`, `--device`… but not a negative number such as `-33.87` or `-33.87,151.2` (a latitude).
    static func looksLikeOption(_ argument: String) -> Bool {
        guard argument.hasPrefix("-"), argument.count > 1 else { return false }
        let second = argument[argument.index(after: argument.startIndex)]
        return !(second.isNumber || second == ".")
    }

    func option(_ names: String...) -> String? { names.lazy.compactMap { options[$0] }.first }
    func has(_ names: String...) -> Bool { names.contains { flags.contains($0) } }

    func intOption(_ names: String..., default fallback: Int? = nil) throws -> Int? {
        guard let text = names.lazy.compactMap({ options[$0] }).first else { return fallback }
        guard let value = Int(text) else { throw CLIError.invalidValue(names[0], text) }
        return value
    }
}

enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidValue(String, String)
    case missingArgument(String)
    case unknownCommand([String])
    case fileExists(String)

    var description: String {
        switch self {
        case .missingValue(let name): "Thiếu giá trị cho \(name)."
        case .invalidValue(let name, let value): "Giá trị không hợp lệ cho \(name): '\(value)'"
        case .missingArgument(let what): "Thiếu tham số: \(what)"
        case .fileExists(let path): "'\(path)' đã tồn tại (dùng --force để ghi đè)."
        case .unknownCommand(let words): "Lệnh không hợp lệ: \(words.joined(separator: " ")). Chạy `adbctl help` để xem danh sách."
        }
    }
}
