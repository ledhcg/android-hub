import Foundation

/// Feeds scrcpy packets through the sample factory into a `ScreenRecorder`. Thread-safe: call `handle`
/// from the video reader thread.
public final class PacketRecorder: @unchecked Sendable {
    public let recorder: ScreenRecorder
    public private(set) var firstFrameSize: FrameSize?

    private let lock = NSLock()
    private var factory = H264SampleFactory()

    public init(url: URL) { recorder = ScreenRecorder(url: url) }

    public func handle(_ packet: VideoPacket) {
        let outputs = lock.withLock { factory.process(packet) }
        for output in outputs {
            switch output {
            case .formatChanged(let size):
                lock.withLock { if firstFrameSize == nil { firstFrameSize = size } }
            case .sample(let sample):
                recorder.append(sample)
            }
        }
    }
}
