import Foundation
import IOKit

/// Reads vendor/product names for attached USB devices from the macOS I/O Registry.
///
/// adb reports nothing but a serial for an `unauthorized` phone; the registry still knows it is
/// a "Xiaomi MI 8", which is what Device Hub-style UIs need to show before pairing succeeds.
public enum MacUSBRegistry {
    public struct Entry: Sendable, Equatable {
        public let vendorName: String?
        public let productName: String?
    }

    /// USB serial number → names.
    public static func entriesBySerial() -> [String: Entry] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [String: Entry] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let serial = string("kUSBSerialNumberString", of: service) ?? string("USB Serial Number", of: service)
            else { continue }
            result[serial] = Entry(
                vendorName: string("USB Vendor Name", of: service),
                productName: string("USB Product Name", of: service)
            )
        }
        return result
    }

    private static func string(_ key: String, of service: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
