import Foundation
import CoreMedia
import VideoToolbox

/// H.264 参数集封装，Annex B 格式
struct H264ParameterSets {
    let sps: Data
    let pps: Data

    var annexBData: Data {
        var data = Data()
        data.reserveCapacity(sps.count + pps.count + 8)
        data.append(startCode)
        data.append(sps)
        data.append(startCode)
        data.append(pps)
        return data
    }
}

private let startCode: Data = Data([0x00, 0x00, 0x00, 0x01])

/// 从 H.264 CMFormatDescription 中提取 SPS/PPS
func extractParameterSets(from formatDescription: CMFormatDescription?) -> H264ParameterSets? {
    guard let fmt = formatDescription else { return nil }

    func parameterSet(at index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size: Int = 0
        var paramCount: Int = 0
        var nalUnitHeaderLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fmt,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: &paramCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard status == noErr, let pointer = pointer, size > 0 else { return nil }
        return Data(bytes: pointer, count: size)
    }

    guard let sps = parameterSet(at: 0),
          let pps = parameterSet(at: 1) else { return nil }
    return H264ParameterSets(sps: sps, pps: pps)
}

/// 将 VideoToolbox 输出的 AVCC（4 字节长度前缀）转为 Annex B（start code）
func convertAVCCToAnnexB(_ data: Data) -> Data {
    var result = Data()
    result.reserveCapacity(data.count + 16)
    var offset = 0

    while offset + 4 <= data.count {
        let nalLength = UInt32(data[offset]) << 24 |
                        UInt32(data[offset + 1]) << 16 |
                        UInt32(data[offset + 2]) << 8 |
                        UInt32(data[offset + 3])
        let nalStart = offset + 4
        let nalEnd = nalStart + Int(nalLength)
        guard nalEnd <= data.count else { break }

        result.append(startCode)
        result.append(contentsOf: data[nalStart..<nalEnd])
        offset = nalEnd
    }

    return result
}

/// 判断 CMSampleBuffer 是否为关键帧
func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) else {
        return true
    }
    let count = CFArrayGetCount(attachments)
    for i in 0..<count {
        guard let raw = CFArrayGetValueAtIndex(attachments, i) else { continue }
        let dict = unsafeBitCast(raw, to: CFDictionary.self)
        let key = kCMSampleAttachmentKey_NotSync as NSString
        let value = CFDictionaryGetValue(dict, Unmanaged.passUnretained(key).toOpaque())
        if let value = value {
            let boolValue = unsafeBitCast(value, to: CFBoolean.self)
            if CFBooleanGetValue(boolValue) {
                return false
            }
        }
    }
    return true
}
