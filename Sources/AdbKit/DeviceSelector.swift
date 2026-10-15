import Foundation

/// Turns the user's `--device <something>` into exactly one attached `Device`.
///
/// A device query (serial or name) is resolved in
/// tiers, strictest first; the first tier that matches anything decides:
///
///  1. exact serial (case-sensitive)
///  2. case-insensitive exact serial, display name, model or codename
///  3. case-insensitive prefix of the serial or display name (like a short git hash)
///
/// Within a tier, more than one match is an error that lists the candidates — a script must never
/// act on the wrong phone. With no query, a lone device is chosen automatically (even if it is
/// `unauthorized`, so the user gets the actionable authorization error instead of a vague one).
public enum DeviceSelector {
    public static func resolve(_ query: String?, among devices: [Device]) throws -> Device {
        guard let rawQuery = query?.trimmingCharacters(in: .whitespaces), !rawQuery.isEmpty else {
            if devices.count == 1 { return devices[0] }
            throw AdbError.noDeviceSpecified(candidates: devices.map(\.serial))
        }

        let needle = rawQuery.lowercased()
        func names(_ device: Device) -> [String] {
            [device.serial, device.displayName, device.model, device.codename, device.usbProductName]
                .compactMap { $0?.lowercased() }
        }

        let tiers: [(Device) -> Bool] = [
            { $0.serial == rawQuery },
            { names($0).contains(needle) },
            { [$0.serial.lowercased(), $0.displayName.lowercased()].contains { $0.hasPrefix(needle) } },
        ]

        for matches in tiers {
            let hits = devices.filter(matches)
            if hits.count == 1 { return hits[0] }
            if hits.count > 1 {
                throw AdbError.ambiguousDevice(query: rawQuery, candidates: hits.map { "\($0.displayName) (\($0.serial))" })
            }
        }
        throw AdbError.deviceNotFound(rawQuery)
    }
}
