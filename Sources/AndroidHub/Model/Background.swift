import Foundation

/// Runs blocking adb work off the main thread. adb calls are synchronous socket I/O, so every UI
/// action funnels through here instead of stalling the interface.
func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) { try work() }.value
}

struct AlertMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

extension Error {
    /// Human-readable text for alerts (adbctl errors already carry Vietnamese guidance).
    var userMessage: String { "\(self)" }
}

func desktopURL(_ name: String) -> URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.appendingPathComponent(name)
}

func fileTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return formatter.string(from: Date())
}
