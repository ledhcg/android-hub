import Foundation

public enum AdbError: Error, Sendable, Equatable {
    case adbNotFound
    case serverUnreachable(String)
    case unexpectedEOF
    case io(String)
    case protocolViolation(String)
    /// The adb server answered `FAIL` with this message.
    case adbFailure(String)

    case deviceNotFound(String)
    case deviceUnauthorized(serial: String)
    case deviceOffline(serial: String)

    case noDeviceSpecified(candidates: [String])
    case ambiguousDevice(query: String, candidates: [String])
}

extension AdbError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .adbNotFound:
            return "Không tìm thấy `adb`. Đặt ANDROID_HOME hoặc thêm platform-tools vào PATH."
        case .serverUnreachable(let detail):
            return "Không kết nối được adb server: \(detail)"
        case .unexpectedEOF:
            return "adb server đóng kết nối đột ngột."
        case .io(let detail):
            return "Lỗi I/O: \(detail)"
        case .protocolViolation(let detail):
            return "Phản hồi adb không hợp lệ: \(detail)"
        case .adbFailure(let message):
            return "adb từ chối yêu cầu: \(message)"
        case .deviceNotFound(let id):
            return "Không thấy thiết bị '\(id)'."
        case .deviceUnauthorized(let serial):
            return """
                Thiết bị \(serial) chưa cấp quyền USB debugging cho máy này.
                Mở khoá điện thoại, bấm Allow ở hộp thoại "Allow USB debugging?" \
                (hoặc thu hồi quyền gỡ lỗi USB trong Tuỳ chọn nhà phát triển rồi cắm lại cáp).
                """
        case .deviceOffline(let serial):
            return "Thiết bị \(serial) đang offline. Thử rút cáp cắm lại hoặc `adb reconnect`."
        case .noDeviceSpecified(let candidates):
            return "Cần chỉ định --device. Thiết bị hiện có: \(candidates.isEmpty ? "(không có)" : candidates.joined(separator: ", "))"
        case .ambiguousDevice(let query, let candidates):
            return "'\(query)' khớp nhiều thiết bị: \(candidates.joined(separator: ", "))"
        }
    }
}
