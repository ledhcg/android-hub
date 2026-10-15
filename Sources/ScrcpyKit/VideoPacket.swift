import CoreMedia
import Foundation

/// One packet from the video socket (12-byte header already stripped).
public struct VideoPacket: Sendable, Equatable {
    public let isConfig: Bool
    public let isKeyFrame: Bool
    /// Presentation time in microseconds; meaningless for config packets.
    public let ptsMicroseconds: Int64
    public let data: Data

    public init(isConfig: Bool, isKeyFrame: Bool, ptsMicroseconds: Int64, data: Data) {
        self.isConfig = isConfig
        self.isKeyFrame = isKeyFrame
        self.ptsMicroseconds = ptsMicroseconds
        self.data = data
    }

    /// Splits the 64-bit "flags + PTS" header word: bit 63 = config, bit 62 = key frame.
    public init(header: UInt64, data: Data) {
        self.init(
            isConfig: header & (1 << 63) != 0, isKeyFrame: header & (1 << 62) != 0,
            ptsMicroseconds: Int64(header & ((1 << 62) - 1)), data: data)
    }
}

public struct FrameSize: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Turns the packet stream into `CMSampleBuffer`s. The config packet (SPS+PPS) defines the format
/// description; a new config (rotation, resize) simply replaces it and the next key frame follows.
public struct H264SampleFactory {
    public private(set) var formatDescription: CMVideoFormatDescription?
    public private(set) var frameSize: FrameSize?

    public init() {}

    public enum Output {
        /// The format changed; `size` is the new decoded frame size.
        case formatChanged(FrameSize)
        case sample(CMSampleBuffer)
    }

    public mutating func process(_ packet: VideoPacket) -> [Output] {
        var outputs: [Output] = []

        // Config packets, and key frames that repeat the parameter sets in-band, both update the format.
        if let sets = AnnexB.parameterSets(in: packet.data), let description = Self.makeFormat(sets) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let size = FrameSize(width: Int(dimensions.width), height: Int(dimensions.height))
            if formatDescription == nil || !CMFormatDescriptionEqual(formatDescription!, otherFormatDescription: description) {
                formatDescription = description
                frameSize = size
                outputs.append(.formatChanged(size))
            }
        }
        if packet.isConfig { return outputs }

        guard let formatDescription else { return outputs }  // no SPS/PPS yet: drop until a key frame arrives
        let payload = AnnexB.toAVCC(packet.data)
        guard !payload.isEmpty, let sample = Self.makeSample(payload, packet: packet, format: formatDescription) else { return outputs }
        outputs.append(.sample(sample))
        return outputs
    }

    static func makeFormat(_ sets: AnnexB.ParameterSets) -> CMVideoFormatDescription? {
        var description: CMVideoFormatDescription?
        let status = sets.sps.withUnsafeBytes { spsBuffer in
            sets.pps.withUnsafeBytes { ppsBuffer -> OSStatus in
                let pointers = [
                    spsBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBuffer.bindMemory(to: UInt8.self).baseAddress!,
                ]
                let sizes = [sets.sps.count, sets.pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        return status == noErr ? description : nil
    }

    static func makeSample(_ payload: Data, packet: VideoPacket, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: payload.count, flags: 0, blockBufferOut: &block) == noErr,
            let block,
            payload.withUnsafeBytes({
                CMBlockBufferReplaceDataBytes(
                    with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
            }) == noErr
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: packet.ptsMicroseconds, timescale: 1_000_000),
            decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
            let sample
        else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            if !packet.isKeyFrame {
                CFDictionarySetValue(
                    dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return sample
    }
}
