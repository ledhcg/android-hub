import Foundation

/// H.264 Annex-B helpers. MediaCodec emits start-code delimited NAL units; CoreMedia wants
/// length-prefixed (AVCC) samples plus out-of-band SPS/PPS.
public enum AnnexB {
    public enum NALType: UInt8 {
        case slice = 1, idr = 5, sei = 6, sps = 7, pps = 8, accessUnitDelimiter = 9
    }

    /// Byte ranges of each NAL unit's payload (start codes excluded).
    public static func nalUnits(in data: Data) -> [Range<Int>] {
        let bytes = [UInt8](data)
        var starts: [(payload: Int, codeStart: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 {
                    starts.append((i + 3, i))
                    i += 3
                    continue
                }
                if i + 3 < bytes.count, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                    starts.append((i + 4, i))
                    i += 4
                    continue
                }
            }
            i += 1
        }
        var ranges: [Range<Int>] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].codeStart : bytes.count
            if start.payload < end { ranges.append(start.payload..<end) }
        }
        return ranges
    }

    public static func nalType(_ data: Data, _ range: Range<Int>) -> UInt8 {
        data[data.startIndex + range.lowerBound] & 0x1F
    }

    public struct ParameterSets: Equatable {
        public var sps: Data
        public var pps: Data
    }

    /// First SPS and PPS found in `data`, if both are present.
    public static func parameterSets(in data: Data) -> ParameterSets? {
        var sps: Data?
        var pps: Data?
        for range in nalUnits(in: data) {
            let slice = data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
            switch nalType(data, range) {
            case NALType.sps.rawValue where sps == nil: sps = slice
            case NALType.pps.rawValue where pps == nil: pps = slice
            default: break
            }
        }
        guard let sps, let pps else { return nil }
        return ParameterSets(sps: sps, pps: pps)
    }

    /// Rewrites start codes as 4-byte big-endian lengths and drops parameter sets / delimiters
    /// (they live in the format description, not in the samples).
    public static func toAVCC(_ data: Data) -> Data {
        var out = Data()
        for range in nalUnits(in: data) {
            let type = nalType(data, range)
            if type == NALType.sps.rawValue || type == NALType.pps.rawValue || type == NALType.accessUnitDelimiter.rawValue { continue }
            let length = UInt32(range.count)
            out.append(contentsOf: [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
            out.append(data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)))
        }
        return out
    }
}
