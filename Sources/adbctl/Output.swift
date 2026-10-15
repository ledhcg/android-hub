import AdbKit
import Foundation

struct AnyEncodable: Encodable {
    private let encodeFunction: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeFunction = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeFunction(encoder) }
}

/// Builds a JSON object whose values have different types.
func obj(_ pairs: (String, any Encodable)...) -> [String: AnyEncodable] {
    Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, AnyEncodable($0.1)) })
}

/// What a command produced: an optional machine-readable result and a human renderer.
struct CommandOutput {
    var json: AnyEncodable?
    var human: () -> Void

    init(json: some Encodable, human: @escaping () -> Void = {}) {
        self.json = AnyEncodable(json)
        self.human = human
    }

    init(human: @escaping () -> Void = {}) {
        json = nil
        self.human = human
    }
}

struct Envelope: Encodable {
    struct Info: Encodable {
        let command: String
        let jsonVersion = 1
        let outcome: String
    }
    struct Failure: Encodable { let message: String }

    let info: Info
    let result: AnyEncodable?
    let error: Failure?
}

func writeJSON(_ envelope: Envelope, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    if path == "-" {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    } else {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
}

/// Prints rows as an aligned table with a header and a rule.
func printTable(_ header: [String], _ rows: [[String]]) {
    let widths = header.indices.map { column in
        (rows.map { $0[column].count } + [header[column].count]).max()! + 2
    }
    print(zip(header, widths).map { pad($0, $1) }.joined().trimmingCharacters(in: .whitespaces))
    print(String(repeating: "-", count: widths.reduce(0, +)))
    for row in rows { print(zip(row, widths).map { pad($0, $1) }.joined().trimmingCharacters(in: .whitespaces)) }
}

func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func expandPath(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

/// Refuses to clobber an existing local file unless `--force` was given.
func ensureWritable(_ url: URL, _ arguments: Arguments) throws {
    if !arguments.has("--force"), FileManager.default.fileExists(atPath: url.path) { throw CLIError.fileExists(url.path) }
}

func conflictPolicy(_ arguments: Arguments) -> ConflictPolicy { arguments.has("--force") ? .overwrite : .refuse }
