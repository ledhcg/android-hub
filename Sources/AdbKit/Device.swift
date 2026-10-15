import Foundation

public enum DeviceState: Sendable, Equatable, Hashable, Codable {
    case device
    case offline
    case unauthorized
    case authorizing
    case noPermissions
    case recovery
    case sideload
    case bootloader
    case unknown(String)

    public init(adbString: String) {
        switch adbString {
        case "device": self = .device
        case "offline": self = .offline
        case "unauthorized": self = .unauthorized
        case "authorizing": self = .authorizing
        case "no permissions": self = .noPermissions
        case "recovery": self = .recovery
        case "sideload": self = .sideload
        case "bootloader": self = .bootloader
        default: self = .unknown(adbString)
        }
    }

    public var rawValue: String {
        switch self {
        case .device: "device"
        case .offline: "offline"
        case .unauthorized: "unauthorized"
        case .authorizing: "authorizing"
        case .noPermissions: "no permissions"
        case .recovery: "recovery"
        case .sideload: "sideload"
        case .bootloader: "bootloader"
        case .unknown(let value): value
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(adbString: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ConnectionKind: String, Sendable, Codable {
    case usb
    case network
    case emulator
}

public struct Device: Sendable, Equatable, Codable, Identifiable {
    public var id: String { serial }

    public var serial: String
    public var state: DeviceState
    public var connection: ConnectionKind
    /// Bus path such as `0-1`, present for USB devices.
    public var usbPath: String?
    public var product: String?
    public var model: String?
    public var codename: String?
    public var transportId: Int?

    /// Filled from the macOS USB registry, so an `unauthorized` device still has a human name.
    public var usbVendorName: String?
    public var usbProductName: String?

    public init(
        serial: String, state: DeviceState, connection: ConnectionKind,
        usbPath: String? = nil, product: String? = nil, model: String? = nil,
        codename: String? = nil, transportId: Int? = nil,
        usbVendorName: String? = nil, usbProductName: String? = nil
    ) {
        self.serial = serial
        self.state = state
        self.connection = connection
        self.usbPath = usbPath
        self.product = product
        self.model = model
        self.codename = codename
        self.transportId = transportId
        self.usbVendorName = usbVendorName
        self.usbProductName = usbProductName
    }

    public var isReady: Bool { state == .device }

    /// Best human-readable name available: adb model, else USB registry, else the serial.
    public var displayName: String {
        if let model, !model.isEmpty { return model.replacingOccurrences(of: "_", with: " ") }
        if let usbProductName, !usbProductName.isEmpty {
            if let usbVendorName, !usbProductName.localizedCaseInsensitiveContains(usbVendorName) {
                return "\(usbVendorName) \(usbProductName)"
            }
            return usbProductName
        }
        return serial
    }
}
