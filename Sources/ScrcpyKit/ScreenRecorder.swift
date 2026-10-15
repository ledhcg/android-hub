import AVFoundation
import CoreMedia
import Foundation

/// Writes the H.264 stream straight into an MP4 without re-encoding (passthrough).
///
/// Each frame is written one step late so it can be given an explicit duration (next PTS − own PTS).
/// The device sends nothing while the screen is static, so the final frame is held until `finish()`
/// is called — the file's length matches wall-clock time rather than the last screen change.
///
/// A rotation or resize changes the SPS, which cannot live in the same MP4 track, so the recorder
/// transparently starts a new numbered segment (`name.mp4`, `name-2.mp4`, ...).
public final class ScreenRecorder: @unchecked Sendable {
    public private(set) var segments: [URL] = []
    public private(set) var frameCount = 0

    private let baseURL: URL
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var currentFormat: CMFormatDescription?
    private var pending: CMSampleBuffer?
    private var finished = false

    public init(url: URL) { baseURL = url }

    /// Appends one frame. Frames before the first key frame are skipped.
    public func append(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let format = CMSampleBufferGetFormatDescription(sample) else { return }

        let isKeyFrame = Self.isKeyFrame(sample)
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if let currentFormat, !CMFormatDescriptionEqual(currentFormat, otherFormatDescription: format) {
            guard isKeyFrame else { return }
            flushPending(until: time)
            closeSegment()
        }
        if writer == nil {
            guard isKeyFrame, startSegment(format: format, at: time) else { return }
        }
        if let pending { write(pending, until: time) }
        pending = sample
    }

    /// Finalises the file(s) and returns every segment written.
    @discardableResult
    public func finish() async -> [URL] {
        let toFinish: AVAssetWriter? = lock.withLock {
            finished = true
            if let last = pending, let first = lastKnownStart {
                // Hold the last frame until "now" (mapped onto the PTS timeline of this segment).
                let elapsed = CMTime(seconds: Date().timeIntervalSince(first.wall), preferredTimescale: 1_000_000)
                write(last, until: CMTimeAdd(first.pts, elapsed))
            } else if let last = pending {
                write(last, until: CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(last), CMTime(value: 1, timescale: 30)))
            }
            pending = nil
            input?.markAsFinished()
            defer { writer = nil; input = nil }
            return writer
        }
        if let toFinish { await toFinish.finishWriting() }
        return lock.withLock { segments }
    }

    // MARK: Internals (call with `lock` held)

    private var lastKnownStart: (pts: CMTime, wall: Date)?

    private func startSegment(format: CMFormatDescription, at time: CMTime) -> Bool {
        let index = segments.count + 1
        let url =
            index == 1
            ? baseURL
            : baseURL.deletingLastPathComponent().appendingPathComponent(
                "\(baseURL.deletingPathExtension().lastPathComponent)-\(index).\(baseURL.pathExtension)")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        self.input = input
        currentFormat = format
        lastKnownStart = (time, Date())
        segments.append(url)
        return true
    }

    /// Writes `sample` with a duration reaching to `end`.
    private func write(_ sample: CMSampleBuffer, until end: CMTime) {
        guard let input, input.isReadyForMoreMediaData else { return }
        let start = CMSampleBufferGetPresentationTimeStamp(sample)
        var duration = CMTimeSubtract(end, start)
        if !duration.isValid || duration <= .zero { duration = CMTime(value: 1, timescale: 60) }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: start, decodeTimeStamp: start)
        var retimed: CMSampleBuffer?
        guard
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleBufferOut: &retimed) == noErr,
            let retimed
        else { return }
        if input.append(retimed) { frameCount += 1 }
    }

    private func flushPending(until end: CMTime) {
        if let pending { write(pending, until: end) }
        pending = nil
    }

    private func closeSegment() {
        guard let writer else { return }
        input?.markAsFinished()
        writer.finishWriting {}
        self.writer = nil
        input = nil
        currentFormat = nil
    }

    static func isKeyFrame(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false),
            CFArrayGetCount(attachments) > 0
        else { return true }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
        return !CFDictionaryContainsKey(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
    }
}
