import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

protocol EncoderDelegate: AnyObject {
    func encoder(_ encoder: Encoder, didOutputAnnexBFrame data: Data, isKeyframe: Bool, sequence: UInt64, timestampNs: UInt64, encodeDurationMs: Double)
    func encoder(_ encoder: Encoder, didOutputParameterSets parameterSets: H264ParameterSets)
}

final class Encoder {
    weak var delegate: EncoderDelegate?

    private var session: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private let fps: Double
    private let bitrate: Int
    private var sequence: UInt64 = 0
    private var currentFormatDescription: CMFormatDescription?
    private var pendingFormatDescription: CMFormatDescription?

    init(width: Int32, height: Int32, fps: Double, bitrate: Int) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
    }

    func start() -> Error? {
        let callback: VTCompressionOutputCallback = { refcon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
            guard let refcon = refcon, let sampleBuffer = sampleBuffer else { return }
            if status != noErr {
                let encoder = Unmanaged<Encoder>.fromOpaque(refcon).takeUnretainedValue()
                encoder.logVTError("encode", status: status)
                return
            }
            let encoder = Unmanaged<Encoder>.fromOpaque(refcon).takeUnretainedValue()
            encoder.handleEncodedFrame(sampleBuffer: sampleBuffer, sourceFrameRefCon: sourceFrameRefCon)
        }

        let pixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let imageBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormatType,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        var sessionRef: VTCompressionSession?
        let createStatus = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: imageBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &sessionRef
        )

        guard createStatus == noErr, let session = sessionRef else {
            return EncoderError.failedToCreateSession(createStatus)
        }

        let properties: [String: Any] = [
            kVTCompressionPropertyKey_RealTime as String: true,
            kVTCompressionPropertyKey_ProfileLevel as String: kVTProfileLevel_H264_Main_AutoLevel as String,
            kVTCompressionPropertyKey_AverageBitRate as String: bitrate,
            kVTCompressionPropertyKey_DataRateLimits as String: [bitrate / 8, 1],
            kVTCompressionPropertyKey_MaxKeyFrameInterval as String: Int32(fps * 2),
            kVTCompressionPropertyKey_AllowFrameReordering as String: false,
            kVTCompressionPropertyKey_H264EntropyMode as String: kVTH264EntropyMode_CABAC as String
        ]

        let propsStatus = VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary)
        guard propsStatus == noErr else {
            return EncoderError.failedToConfigureSession(propsStatus)
        }

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            return EncoderError.failedToPrepareSession(prepareStatus)
        }

        self.session = session
        return nil
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let session = session else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let sequence = nextSequence()
        let startTimeNs = DispatchTime.now().uptimeNanoseconds
        let context = FrameContext(sequence: sequence, startTimeNs: startTimeNs, timestampNs: UInt64(pts.value))

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: duration.isValid ? duration : CMTime.invalid,
            frameProperties: nil,
            sourceFrameRefcon: Unmanaged.passRetained(context).toOpaque(),
            infoFlagsOut: nil
        )

        if status != noErr {
            logVTError("encode frame", status: status)
        }
    }

    func stop(completion: @escaping () -> Void) {
        guard let session = session else {
            completion()
            return
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: CMTime.invalid)
        self.session = nil
        completion()
    }

    // MARK: - Callback handling

    private func handleEncodedFrame(sampleBuffer: CMSampleBuffer, sourceFrameRefCon: UnsafeMutableRawPointer?) {
        guard let raw = sourceFrameRefCon else { return }
        let context = Unmanaged<FrameContext>.fromOpaque(raw).takeRetainedValue()
        let encodeDurationNs = DispatchTime.now().uptimeNanoseconds - context.startTimeNs
        let encodeDurationMs = Double(encodeDurationNs) / 1_000_000.0

        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        if let formatDescription = formatDescription, currentFormatDescription == nil || !CMFormatDescriptionEqual(formatDescription, otherFormatDescription: currentFormatDescription!) {
            currentFormatDescription = formatDescription
            if let parameterSets = extractParameterSets(from: formatDescription) {
                delegate?.encoder(self, didOutputParameterSets: parameterSets)
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == noErr, let pointer = dataPointer else { return }

        let avccData = Data(bytes: pointer, count: totalLength)
        let annexBData = convertAVCCToAnnexB(avccData)
        let keyframe = isKeyframe(sampleBuffer)

        delegate?.encoder(self, didOutputAnnexBFrame: annexBData, isKeyframe: keyframe, sequence: context.sequence, timestampNs: context.timestampNs, encodeDurationMs: encodeDurationMs)
    }

    private func nextSequence() -> UInt64 {
        sequence += 1
        return sequence
    }

    private func logVTError(_ operation: String, status: OSStatus) {
        let fourcc = String(format: "%c%c%c%c",
                            (status >> 24) & 0xff,
                            (status >> 16) & 0xff,
                            (status >> 8) & 0xff,
                            status & 0xff)
        Logger.writeLine("[ERROR] VideoToolbox \(operation) failed: \(status) (\(fourcc))")
    }
}

private final class FrameContext {
    let sequence: UInt64
    let startTimeNs: UInt64
    let timestampNs: UInt64

    init(sequence: UInt64, startTimeNs: UInt64, timestampNs: UInt64) {
        self.sequence = sequence
        self.startTimeNs = startTimeNs
        self.timestampNs = timestampNs
    }
}

enum EncoderError: LocalizedError {
    case failedToCreateSession(OSStatus)
    case failedToConfigureSession(OSStatus)
    case failedToPrepareSession(OSStatus)

    var errorDescription: String? {
        switch self {
        case .failedToCreateSession(let status):
            return "创建 VideoToolbox 编码会话失败: \(status)"
        case .failedToConfigureSession(let status):
            return "配置编码会话失败: \(status)"
        case .failedToPrepareSession(let status):
            return "准备编码会话失败: \(status)"
        }
    }
}
