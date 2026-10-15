import AdbKit
import Foundation

private func parseBool(_ text: String) throws -> Bool {
    switch text.lowercased() {
    case "on", "true", "yes", "1", "enable": return true
    case "off", "false", "no", "0", "disable": return false
    default: throw CLIError.invalidValue("on|off", text)
    }
}

/// Maps `device settings set <name> <value...>` to a `SettingChange`.
func parseSettingChange(name: String, values: [String]) throws -> SettingChange {
    func value(_ index: Int = 0) throws -> String {
        guard index < values.count else { throw CLIError.missingArgument("value for '\(name)'") }
        return values[index]
    }
    func number<T: LosslessStringConvertible>(_ text: String) throws -> T {
        guard let parsed = T(text) else { throw CLIError.invalidValue(name, text) }
        return parsed
    }

    switch name {
    case "appearance":
        guard let mode = AppearanceMode(rawValue: try value()) else { throw CLIError.invalidValue(name, try value()) }
        return .appearance(mode)
    case "font-scale": return .fontScale(try number(try value()))
    case "animation-scale": return .animationScale(try number(try value()))
    case "auto-rotate": return .autoRotate(try parseBool(try value()))
    case "rotation":
        let text = try value()
        let table: [String: DeviceRotation] = [
            "0": .portrait, "portrait": .portrait, "1": .landscapeLeft, "landscape-left": .landscapeLeft,
            "2": .portraitUpsideDown, "portrait-upside-down": .portraitUpsideDown,
            "3": .landscapeRight, "landscape-right": .landscapeRight,
        ]
        guard let rotation = table[text] else { throw CLIError.invalidValue(name, text) }
        return .rotation(rotation)
    case "wifi": return .wifi(try parseBool(try value()))
    case "mobile-data": return .mobileData(try parseBool(try value()))
    case "airplane-mode": return .airplaneMode(try parseBool(try value()))
    case "bluetooth": return .bluetooth(try parseBool(try value()))
    case "brightness": return .brightness(try number(try value()))
    case "auto-brightness": return .autoBrightness(try parseBool(try value()))
    case "stay-awake": return .stayAwake(try parseBool(try value()))
    case "show-touches": return .showTouches(try parseBool(try value()))
    case "pointer-location": return .pointerLocation(try parseBool(try value()))
    case "screen-timeout":
        let seconds: Int = try number(try value())
        return .screenTimeout(milliseconds: seconds * 1000)
    case "color-inversion": return .colorInversion(try parseBool(try value()))
    case "high-contrast-text": return .highContrastText(try parseBool(try value()))
    case "color-correction":
        let text = try value()
        if text == "off" { return .colorCorrection(nil) }
        let table: [String: ColorCorrection] = [
            "monochromacy": .monochromacy, "protanomaly": .protanomaly, "deuteranomaly": .deuteranomaly, "tritanomaly": .tritanomaly,
        ]
        guard let mode = table[text] else { throw CLIError.invalidValue(name, text) }
        return .colorCorrection(mode)
    case "do-not-keep-activities": return .doNotKeepActivities(try parseBool(try value()))
    case "volume": return .mediaVolume(try number(try value()))
    case "display-size":
        let text = try value()
        if text == "reset" { return .resetDisplaySize }
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { throw CLIError.invalidValue(name, text) }
        return .displaySize(width: parts[0], height: parts[1])
    case "display-density":
        let text = try value()
        return text == "reset" ? .resetDisplayDensity : .displayDensity(try number(text))
    case "battery-level": return .batteryLevel(try number(try value()))
    case "battery-status":
        let table: [String: BatteryStatus] = [
            "unknown": .unknown, "charging": .charging, "discharging": .discharging, "not-charging": .notCharging, "full": .full,
        ]
        guard let status = table[try value()] else { throw CLIError.invalidValue(name, try value()) }
        return .batteryStatus(status)
    case "battery-power":
        let sources = Set(try value().split(separator: ",").map(String.init))
        return .batteryPower(ac: sources.contains("ac"), usb: sources.contains("usb"), wireless: sources.contains("wireless"))
    case "battery-reset": return .resetBattery
    case "timezone": return .timeZone(try value())
    case "location":
        let parts = try value().split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { throw CLIError.invalidValue(name, try value()) }
        return .location(latitude: parts[0], longitude: parts[1])
    case "network-speed": return .emulatorNetworkSpeed(try value())
    case "network-delay": return .emulatorNetworkDelay(try value())
    case "app-locale":
        let tag = try value(1)
        return .appLocale(package: try value(0), languageTag: tag == "reset" ? nil : tag)
    case "open-locale-settings": return .openLocaleSettings
    default: throw CLIError.invalidValue("setting name", name)
    }
}

func registerSettingsCommands() {
    register("device settings get", "Read current settings (appearance, font size, rotation, network, accessibility...)") { context in
        let snapshot = try context.client.settingsSnapshot(serial: try context.serial())
        return CommandOutput(json: snapshot) {
            func row(_ label: String, _ value: (some CustomStringConvertible)?) {
                print(pad(label, 24) + (value.map { "\($0)" } ?? "-"))
            }
            row("appearance", snapshot.appearance?.rawValue)
            row("font-scale", snapshot.fontScale)
            row("animation-scale", snapshot.animationScale)
            row("auto-rotate", snapshot.autoRotate)
            row("rotation", snapshot.rotation.map { "\($0)" })
            row("wifi", snapshot.wifi)
            row("mobile-data", snapshot.mobileData)
            row("airplane-mode", snapshot.airplaneMode)
            row("bluetooth", snapshot.bluetooth)
            row("brightness", snapshot.brightness)
            row("auto-brightness", snapshot.autoBrightness)
            row("stay-awake", snapshot.stayAwake)
            row("show-touches", snapshot.showTouches)
            row("pointer-location", snapshot.pointerLocation)
            row("screen-timeout (ms)", snapshot.screenTimeoutMilliseconds)
            row("color-inversion", snapshot.colorInversion)
            row("high-contrast-text", snapshot.highContrastText)
            row("color-correction", snapshot.colorCorrection.map { "\($0)" })
            row("do-not-keep-activities", snapshot.doNotKeepActivities)
            row("volume", snapshot.mediaVolume.map { "\($0)/\(snapshot.mediaVolumeMax ?? 0)" })
            row("locale", snapshot.locale)
            row("timezone", snapshot.timeZone)
        }
    }

    register(
        "device settings set", "<name> <value>", "Change a setting (see `--help` for the list of names)",
        detail: """
            Setting names and values:
              appearance light|dark|auto          font-scale 0.85–2.0        animation-scale 0–10
              auto-rotate on|off                  rotation portrait|landscape-left|portrait-upside-down|landscape-right
              wifi|mobile-data|airplane-mode|bluetooth on|off
              brightness 0–255                    auto-brightness on|off     volume N
              stay-awake|show-touches|pointer-location on|off               screen-timeout <seconds>
              color-inversion|high-contrast-text on|off                     do-not-keep-activities on|off
              color-correction off|monochromacy|protanomaly|deuteranomaly|tritanomaly
              display-size WxH|reset              display-density <dpi>|reset
              battery-level 0–100                 battery-status unknown|charging|discharging|not-charging|full
              battery-power ac,usb,wireless|none  battery-reset
              timezone <Asia/Ho_Chi_Minh>         location <latitude>,<longitude>
              network-speed|network-delay <profile>   (emulator only)
              app-locale <package> <vi-VN|reset>  open-locale-settings
            """
    ) { context in
        let name = try context.positional(0, "setting name")
        let change = try parseSettingChange(name: name, values: Array(context.rest.dropFirst()))
        let serial = try context.serial()
        try context.client.apply(change, serial: serial)
        return CommandOutput(json: ["applied": name]) { print("Applied: \(name)") }
    }
}
