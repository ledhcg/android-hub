import Foundation
import ScrcpyKit

/// Fans one scrcpy video stream out to every canvas showing the device (main window, compact windows).
///
/// Each canvas decodes on its own, so a view that appears mid-stream is first fed the cached config
/// packet (SPS/PPS) and then a key frame is requested by the controller.
final class MirrorHub: @unchecked Sendable {
    private struct Weak { weak var view: MirrorNSView? }

    private let lock = NSLock()
    private var views: [Weak] = []
    private var lastConfig: VideoPacket?

    func add(_ view: MirrorNSView) {
        let config: VideoPacket? = lock.withLock {
            views.removeAll { $0.view == nil }
            views.append(Weak(view: view))
            return lastConfig
        }
        if let config { view.handle(packet: config) }
    }

    func remove(_ view: MirrorNSView) {
        lock.withLock { views.removeAll { $0.view == nil || $0.view === view } }
    }

    /// Called on the video thread.
    func dispatch(_ packet: VideoPacket) {
        let targets: [MirrorNSView] = lock.withLock {
            if packet.isConfig { lastConfig = packet }
            return views.compactMap(\.view)
        }
        for view in targets { view.handle(packet: packet) }
    }

    /// A new session starts from scratch.
    func reset() {
        let targets: [MirrorNSView] = lock.withLock {
            lastConfig = nil
            return views.compactMap(\.view)
        }
        DispatchQueue.main.async { targets.forEach { $0.resetVideo() } }
    }

    var hasViews: Bool { lock.withLock { views.contains { $0.view != nil } } }
}
