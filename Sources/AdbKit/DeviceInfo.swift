import Foundation

public struct DeviceInfoDetails: Sendable, Equatable, Codable {
    public struct Size: Sendable, Equatable, Codable {
        public let width: Int
        public let height: Int
    }

    public struct Battery: Sendable, Equatable, Codable {
        public let level: Int?
        public let isCharging: Bool?
        public let poweredBy: [String]
        public let temperatureCelsius: Double?
    }

    public var serial: String
    public var manufacturer: String?
    public var brand: String?
    public var model: String?
    public var marketName: String?
    public var codename: String?
    public var androidVersion: String?
    public var sdkInt: Int?
    public var securityPatch: String?
    public var buildId: String?
    public var primaryABI: String?
    public var isEmulator: Bool
    public var physicalSize: Size?
    public var overrideSize: Size?
    public var physicalDensity: Int?
    public var overrideDensity: Int?
    public var battery: Battery?
}

extension AdbClient {
    private static let sectionMarker = "@@ADBHUB@@"

    /// One shell round-trip: `getprop` + `wm` + `dumpsys battery`, split by marker lines.
    public func deviceInfo(serial: String) throws -> DeviceInfoDetails {
        let marker = Self.sectionMarker
        let script = "getprop; echo \(marker)wm; wm size; wm density; echo \(marker)battery; dumpsys battery"
        let result = try shell(serial: serial, script)
        guard result.exitCode == 0 || !result.stdout.isEmpty else {
            throw AdbError.adbFailure("shell thoát với mã \(result.exitCode): \(result.stderr)")
        }
        return DeviceInfoDetails.parse(output: result.stdout, serial: serial, sectionMarker: marker)
    }
}

extension DeviceInfoDetails {
    static func parse(output: String, serial: String, sectionMarker: String = "@@ADBHUB@@") -> DeviceInfoDetails {
        var sections: [String: [Substring]] = [:]
        var current = "getprop"
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(sectionMarker) {
                current = String(line.dropFirst(sectionMarker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                sections[current, default: []].append(line)
            }
        }

        let props = parseGetprop(sections["getprop"] ?? [])
        func prop(_ keys: String...) -> String? {
            keys.lazy.compactMap { props[$0] }.first { !$0.isEmpty }
        }

        let wm = (sections["wm"] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        func size(_ prefix: String) -> Size? {
            guard let line = wm.first(where: { $0.hasPrefix(prefix) }) else { return nil }
            let parts = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).split(separator: "x")
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
            return Size(width: w, height: h)
        }
        func density(_ prefix: String) -> Int? {
            wm.first(where: { $0.hasPrefix(prefix) })
                .flatMap { Int($0.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)) }
        }

        let hardware = prop("ro.hardware") ?? ""
        return DeviceInfoDetails(
            serial: serial,
            manufacturer: prop("ro.product.manufacturer"),
            brand: prop("ro.product.brand"),
            model: prop("ro.product.model"),
            marketName: prop("ro.product.marketname", "ro.product.odm.marketname", "ro.config.marketing_name"),
            codename: prop("ro.product.device"),
            androidVersion: prop("ro.build.version.release"),
            sdkInt: prop("ro.build.version.sdk").flatMap(Int.init),
            securityPatch: prop("ro.build.version.security_patch"),
            buildId: prop("ro.build.display.id"),
            primaryABI: prop("ro.product.cpu.abi"),
            isEmulator: serial.hasPrefix("emulator-") || hardware == "ranchu" || hardware == "goldfish",
            physicalSize: size("Physical size:"),
            overrideSize: size("Override size:"),
            physicalDensity: density("Physical density:"),
            overrideDensity: density("Override density:"),
            battery: parseBattery(sections["battery"] ?? [])
        )
    }

    /// `[ro.product.model]: [MI 8]` → `["ro.product.model": "MI 8"]`
    static func parseGetprop(_ lines: [Substring]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            guard line.hasPrefix("["), let separator = line.range(of: "]: [") else { continue }
            let key = line[line.index(after: line.startIndex)..<separator.lowerBound]
            var value = line[separator.upperBound...]
            if value.hasSuffix("]") { value = value.dropLast() }
            result[String(key)] = String(value)
        }
        return result
    }

    /// `dumpsys battery` prints indented `key: value` lines (status 2 = charging, 5 = full).
    static func parseBattery(_ lines: [Substring]) -> Battery? {
        var fields: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard !fields.isEmpty else { return nil }

        var poweredBy: [String] = []
        for (key, name) in [("AC powered", "ac"), ("USB powered", "usb"), ("Wireless powered", "wireless")]
        where fields[key] == "true" {
            poweredBy.append(name)
        }
        return Battery(
            level: fields["level"].flatMap(Int.init),
            isCharging: fields["status"].flatMap(Int.init).map { $0 == 2 || $0 == 5 },
            poweredBy: poweredBy,
            temperatureCelsius: fields["temperature"].flatMap(Double.init).map { $0 / 10 }
        )
    }
}
