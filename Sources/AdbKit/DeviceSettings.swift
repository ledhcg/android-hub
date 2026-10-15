import Foundation

public enum AppearanceMode: String, Sendable, Codable, CaseIterable {
    case light, dark, auto
}

/// `Surface.ROTATION_*` as used by the `user_rotation` setting.
public enum DeviceRotation: Int, Sendable, Codable, CaseIterable {
    case portrait = 0
    case landscapeLeft = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
}

public enum ColorCorrection: Int, Sendable, Codable, CaseIterable {
    case monochromacy = 0
    case protanomaly = 11
    case deuteranomaly = 12
    case tritanomaly = 13
}

public enum BatteryStatus: Int, Sendable, Codable, CaseIterable {
    case unknown = 1, charging = 2, discharging = 3, notCharging = 4, full = 5
}

/// Everything the Settings inspector shows, read in a single round trip.
public struct DeviceSettingsSnapshot: Sendable, Equatable, Codable {
    public var appearance: AppearanceMode?
    public var fontScale: Double?
    public var animationScale: Double?
    public var autoRotate: Bool?
    public var rotation: DeviceRotation?
    public var wifi: Bool?
    public var mobileData: Bool?
    public var airplaneMode: Bool?
    public var bluetooth: Bool?
    public var brightness: Int?
    public var autoBrightness: Bool?
    public var stayAwake: Bool?
    public var showTouches: Bool?
    public var pointerLocation: Bool?
    public var screenTimeoutMilliseconds: Int?
    public var colorInversion: Bool?
    public var highContrastText: Bool?
    public var colorCorrection: ColorCorrection?
    public var doNotKeepActivities: Bool?
    public var mediaVolume: Int?
    public var mediaVolumeMax: Int?
    public var locale: String?
    public var timeZone: String?

    public init() {}
}

extension DeviceSettingsSnapshot {
    static let readScript = """
        echo "N:$(cmd uimode night 2>&1 | head -1)"
        for pair in "system font_scale" "global window_animation_scale" "system accelerometer_rotation" \
        "system user_rotation" "global wifi_on" "global mobile_data" "global airplane_mode_on" \
        "global bluetooth_on" "system screen_brightness" "system screen_brightness_mode" \
        "global stay_on_while_plugged_in" "system show_touches" "system pointer_location" \
        "system screen_off_timeout" "secure accessibility_display_inversion_enabled" \
        "secure high_text_contrast_enabled" "secure accessibility_display_daltonizer_enabled" \
        "secure accessibility_display_daltonizer" "global always_finish_activities"; do
          echo "S:${pair#* }=$(settings get ${pair% *} ${pair#* } 2>/dev/null)"
        done
        echo "V:$(cmd media_session volume --stream 3 --get 2>&1 | grep 'volume is')"
        echo "P:locale=$(getprop persist.sys.locale)"
        echo "P:fallbackLocale=$(getprop ro.product.locale)"
        echo "P:timezone=$(getprop persist.sys.timezone)"
        """

    static func parse(_ output: String) -> DeviceSettingsSnapshot {
        var values: [String: String] = [:]
        var night: String?
        var volumeLine: String?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("N:") { night = String(line.dropFirst(2)) }
            else if line.hasPrefix("V:") { volumeLine = String(line.dropFirst(2)) }
            else if line.hasPrefix("S:") || line.hasPrefix("P:"), let equals = line.firstIndex(of: "=") {
                let key = String(line[line.index(line.startIndex, offsetBy: 2)..<equals])
                values[key] = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        func text(_ key: String) -> String? {
            guard let value = values[key], !value.isEmpty, value != "null" else { return nil }
            return value
        }
        func int(_ key: String) -> Int? { text(key).flatMap { Int($0) } }
        func double(_ key: String) -> Double? { text(key).flatMap { Double($0) } }
        func flag(_ key: String) -> Bool? { int(key).map { $0 != 0 } }

        var snapshot = DeviceSettingsSnapshot()
        if let night = night?.lowercased() {
            snapshot.appearance = night.contains("yes") ? .dark : night.contains("no") ? .light : night.contains("auto") ? .auto : nil
        }
        snapshot.fontScale = double("font_scale")
        snapshot.animationScale = double("window_animation_scale")
        snapshot.autoRotate = flag("accelerometer_rotation")
        snapshot.rotation = int("user_rotation").flatMap(DeviceRotation.init(rawValue:))
        snapshot.wifi = flag("wifi_on")
        snapshot.mobileData = flag("mobile_data")
        snapshot.airplaneMode = flag("airplane_mode_on")
        snapshot.bluetooth = flag("bluetooth_on")
        snapshot.brightness = int("screen_brightness")
        snapshot.autoBrightness = int("screen_brightness_mode").map { $0 == 1 }
        snapshot.stayAwake = int("stay_on_while_plugged_in").map { $0 != 0 }
        // Unset (`null`) means "off" for these developer/accessibility toggles.
        snapshot.showTouches = flag("show_touches") ?? false
        snapshot.pointerLocation = flag("pointer_location") ?? false
        snapshot.screenTimeoutMilliseconds = int("screen_off_timeout")
        snapshot.colorInversion = flag("accessibility_display_inversion_enabled") ?? false
        snapshot.highContrastText = flag("high_text_contrast_enabled") ?? false
        if flag("accessibility_display_daltonizer_enabled") == true {
            snapshot.colorCorrection = int("accessibility_display_daltonizer").flatMap(ColorCorrection.init(rawValue:))
        }
        snapshot.doNotKeepActivities = flag("always_finish_activities") ?? false
        snapshot.locale = text("locale") ?? text("fallbackLocale")
        snapshot.timeZone = text("timezone")

        // "volume is 7 in range [0..15]" (Android 12+) — absent or an error message elsewhere.
        if let volumeLine, let match = volumeLine.range(of: #"volume is (\d+) in range \[(\d+)\.\.(\d+)\]"#, options: .regularExpression) {
            let numbers = volumeLine[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count == 3 {
                snapshot.mediaVolume = numbers[0]
                snapshot.mediaVolumeMax = numbers[2]
            }
        }
        return snapshot
    }
}

/// One change made from the Settings inspector. `commands` is the exact shell it runs, so it is
/// trivially unit-testable; `emulatorConsole` holds Android-Emulator-only commands.
public enum SettingChange: Sendable, Equatable {
    case appearance(AppearanceMode)
    case fontScale(Double)
    case animationScale(Double)
    case autoRotate(Bool)
    case rotation(DeviceRotation)
    case wifi(Bool)
    case mobileData(Bool)
    case airplaneMode(Bool)
    case bluetooth(Bool)
    case brightness(Int)
    case autoBrightness(Bool)
    case stayAwake(Bool)
    case showTouches(Bool)
    case pointerLocation(Bool)
    case screenTimeout(milliseconds: Int)
    case colorInversion(Bool)
    case highContrastText(Bool)
    case colorCorrection(ColorCorrection?)
    case doNotKeepActivities(Bool)
    case mediaVolume(Int)
    case displaySize(width: Int, height: Int)
    case resetDisplaySize
    case displayDensity(Int)
    case resetDisplayDensity
    case batteryLevel(Int)
    case batteryStatus(BatteryStatus)
    case batteryPower(ac: Bool, usb: Bool, wireless: Bool)
    case resetBattery
    case timeZone(String)
    case appLocale(package: String, languageTag: String?)
    case openLocaleSettings
    /// Mock GPS fix. Emulator uses `geo fix`; on hardware this relies on `cmd location` test providers.
    case location(latitude: Double, longitude: Double)
    case emulatorNetworkSpeed(String)
    case emulatorNetworkDelay(String)

    public var commands: [String] {
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }
        func word(_ value: Bool) -> String { value ? "enable" : "disable" }
        switch self {
        case .appearance(let mode):
            return ["cmd uimode night \(mode == .dark ? "yes" : mode == .light ? "no" : "auto")"]
        case .fontScale(let scale):
            return ["settings put system font_scale \(Self.decimal(scale))"]
        case .animationScale(let scale):
            let value = Self.decimal(scale)
            return ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]
                .map { "settings put global \($0) \(value)" }
        case .autoRotate(let on):
            return ["settings put system accelerometer_rotation \(bit(on))"]
        case .rotation(let rotation):
            return ["settings put system accelerometer_rotation 0", "settings put system user_rotation \(rotation.rawValue)"]
        case .wifi(let on):
            return ["svc wifi \(word(on))"]
        case .mobileData(let on):
            return ["svc data \(word(on))"]
        case .airplaneMode(let on):
            // `cmd connectivity airplane-mode` exists on Android 11+. Older releases only allow the
            // protected AIRPLANE_MODE broadcast from the system, so fail clearly instead of half-applying.
            return [
                "cmd connectivity airplane-mode \(word(on)) || { echo 'Airplane mode via adb requires Android 11+' >&2; exit 1; }"
            ]
        case .bluetooth(let on):
            return ["cmd bluetooth_manager \(word(on)) 2>/dev/null || svc bluetooth \(word(on))"]
        case .brightness(let level):
            return ["settings put system screen_brightness_mode 0", "settings put system screen_brightness \(min(max(level, 0), 255))"]
        case .autoBrightness(let on):
            return ["settings put system screen_brightness_mode \(bit(on))"]
        case .stayAwake(let on):
            return ["settings put global stay_on_while_plugged_in \(on ? 7 : 0)"]
        case .showTouches(let on):
            return ["settings put system show_touches \(bit(on))"]
        case .pointerLocation(let on):
            return ["settings put system pointer_location \(bit(on))"]
        case .screenTimeout(let milliseconds):
            return ["settings put system screen_off_timeout \(milliseconds)"]
        case .colorInversion(let on):
            return ["settings put secure accessibility_display_inversion_enabled \(bit(on))"]
        case .highContrastText(let on):
            return ["settings put secure high_text_contrast_enabled \(bit(on))"]
        case .colorCorrection(let mode):
            if let mode {
                return [
                    "settings put secure accessibility_display_daltonizer \(mode.rawValue)",
                    "settings put secure accessibility_display_daltonizer_enabled 1",
                ]
            }
            return ["settings put secure accessibility_display_daltonizer_enabled 0"]
        case .doNotKeepActivities(let on):
            return ["settings put global always_finish_activities \(bit(on))"]
        case .mediaVolume(let level):
            return ["cmd media_session volume --stream 3 --set \(max(level, 0))"]
        case .displaySize(let width, let height):
            return ["wm size \(width)x\(height)"]
        case .resetDisplaySize:
            return ["wm size reset"]
        case .displayDensity(let dpi):
            return ["wm density \(dpi)"]
        case .resetDisplayDensity:
            return ["wm density reset"]
        case .batteryLevel(let level):
            return ["dumpsys battery set level \(min(max(level, 0), 100))"]
        case .batteryStatus(let status):
            return ["dumpsys battery set status \(status.rawValue)"]
        case .batteryPower(let ac, let usb, let wireless):
            return [
                "dumpsys battery set ac \(bit(ac))", "dumpsys battery set usb \(bit(usb))",
                "dumpsys battery set wireless \(bit(wireless))",
            ]
        case .resetBattery:
            return ["dumpsys battery reset"]
        case .timeZone(let identifier):
            let quoted = Self.shellQuote(identifier)
            return ["cmd alarm set-timezone \(quoted) 2>/dev/null || service call alarm 3 s16 \(quoted) >/dev/null"]
        case .appLocale(let package, let tag):
            return ["cmd locale set-app-locales \(Self.shellQuote(package)) --locales \(Self.shellQuote(tag ?? ""))"]
        case .openLocaleSettings:
            return ["am start -a android.settings.LOCALE_SETTINGS"]
        case .location(let latitude, let longitude):
            // Hardware fallback: register a test provider owned by the shell and publish a fix.
            let fix = "\(Self.decimal(latitude, digits: 6)),\(Self.decimal(longitude, digits: 6))"
            return [
                "appops set com.android.shell android:mock_location allow 2>/dev/null; "
                    + "cmd location providers add-test-provider gps 2>/dev/null; "
                    + "cmd location providers set-test-provider-enabled gps true && "
                    + "cmd location providers set-test-provider-location gps --location \(fix) --accuracy 5"
            ]
        case .emulatorNetworkSpeed, .emulatorNetworkDelay:
            return []
        }
    }

    /// Commands for the Android Emulator console, run instead of `commands` on an emulator.
    public var emulatorConsole: [String]? {
        switch self {
        case .location(let latitude, let longitude):
            // `geo fix` takes longitude first.
            return ["geo fix \(Self.decimal(longitude, digits: 6)) \(Self.decimal(latitude, digits: 6))"]
        case .emulatorNetworkSpeed(let profile):
            return ["network speed \(Self.consoleToken(profile))"]
        case .emulatorNetworkDelay(let profile):
            return ["network delay \(Self.consoleToken(profile))"]
        default:
            return nil
        }
    }

    public var isEmulatorOnly: Bool {
        switch self {
        case .emulatorNetworkSpeed, .emulatorNetworkDelay: true
        default: false
        }
    }

    static func decimal(_ value: Double, digits: Int = 2) -> String {
        var text = String(format: "%.\(digits)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Console commands are line based; strip anything that could end the line or add a second command.
    static func consoleToken(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0) })
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension AdbClient {
    public func settingsSnapshot(serial: String) throws -> DeviceSettingsSnapshot {
        DeviceSettingsSnapshot.parse(try shell(serial: serial, DeviceSettingsSnapshot.readScript).stdout)
    }

    /// Applies a change, choosing the emulator console or the shell as appropriate.
    public func apply(_ change: SettingChange, serial: String) throws {
        let isEmulator = serial.hasPrefix("emulator-")
        if isEmulator, let console = change.emulatorConsole {
            for command in console { try emulatorCommand(serial: serial, command) }
            return
        }
        if change.isEmulatorOnly {
            throw AdbError.adbFailure("This feature is only available on the Android Emulator.")
        }
        if case .mediaVolume(let target) = change {
            try setMediaVolume(target, serial: serial)
            return
        }
        for command in change.commands { try run(serial: serial, command) }
    }

    /// Sets the music-stream volume; falls back to volume keys when `cmd media_session` ignores the request.
    func setMediaVolume(_ target: Int, serial: String) throws {
        func current() throws -> Int? {
            DeviceSettingsSnapshot.parse("V:" + (try shell(serial: serial, "cmd media_session volume --stream 3 --get 2>&1 | grep 'volume is'").stdout)).mediaVolume
        }
        _ = try? run(serial: serial, "cmd media_session volume --stream 3 --set \(max(target, 0))")
        for _ in 0..<40 {
            guard let level = try current(), level != target else { return }
            try run(serial: serial, "input keyevent \(level < target ? 24 : 25)")
        }
    }
}
