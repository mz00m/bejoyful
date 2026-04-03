import AVFoundation
import UIKit

class VideoExporter {
    enum ExportError: Error {
        case setupFailed
        case cancelled
        case writeFailed(String)
    }

    struct ExportConfig {
        let width: Int
        let height: Int
        let fps: Int
        let duration: Double
        let includeAudio: Bool
    }

    static func export(
        config: ExportConfig,
        renderFrame: @escaping (Int, Double) -> UIImage?,
        audioBuffer: AVAudioPCMBuffer?,
        progress: @escaping (Int, Int) -> Void,
        cancelled: @escaping () -> Bool
    ) async throws -> URL {
        let totalFrames = Int(config.duration * Double(config.fps))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaleidoscope_\(UUID().uuidString).mp4")

        // Clean up any existing file
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.setupFailed
        }

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.width * config.height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: config.width,
                kCVPixelBufferHeightKey as String: config.height,
            ]
        )

        writer.add(videoInput)

        // Audio input (if applicable)
        var audioInput: AVAssetWriterInput?
        if config.includeAudio, let buffer = audioBuffer {
            let audioFormat = buffer.format
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audioFormat.sampleRate,
                AVNumberOfChannelsKey: audioFormat.channelCount,
                AVEncoderBitRateKey: 128000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw ExportError.setupFailed
        }

        writer.startSession(atSourceTime: .zero)

        // Write video frames
        for frame in 0..<totalFrames {
            if cancelled() { throw ExportError.cancelled }

            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            let time = Double(frame) / Double(config.fps)

            guard let image = renderFrame(frame, time) else { continue }
            guard let pixelBuffer = pixelBuffer(from: image, width: config.width, height: config.height) else { continue }

            let presentationTime = CMTime(value: Int64(frame), timescale: CMTimeScale(config.fps))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            await MainActor.run {
                progress(frame + 1, totalFrames)
            }
        }

        videoInput.markAsFinished()

        // Write audio if applicable
        if let audioInput = audioInput, let buffer = audioBuffer {
            await writeAudio(input: audioInput, buffer: buffer, duration: config.duration)
            audioInput.markAsFinished()
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        return outputURL
    }

    private static func writeAudio(input: AVAssetWriterInput, buffer: AVAudioPCMBuffer, duration: Double) async {
        guard let channelData = buffer.floatChannelData else { return }

        let sampleRate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)
        let totalSamples = min(Int(buffer.frameLength), Int(duration * sampleRate))
        let chunkSize = 4096

        var samplesWritten = 0

        while samplesWritten < totalSamples {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }

            let remaining = totalSamples - samplesWritten
            let samplesToWrite = min(chunkSize, remaining)

            guard let sampleBuffer = createAudioSampleBuffer(
                channelData: channelData,
                channels: channels,
                sampleRate: sampleRate,
                offset: samplesWritten,
                count: samplesToWrite
            ) else { break }

            input.append(sampleBuffer)
            samplesWritten += samplesToWrite
        }
    }

    private static func createAudioSampleBuffer(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channels: Int,
        sampleRate: Double,
        offset: Int,
        count: Int
    ) -> CMSampleBuffer? {
        let bytesPerSample = MemoryLayout<Int16>.size
        let dataSize = count * channels * bytesPerSample

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard let block = blockBuffer else { return nil }

        // Convert float to int16
        var rawData = [Int16](repeating: 0, count: count * channels)
        for i in 0..<count {
            for ch in 0..<channels {
                let sample = channelData[ch][offset + i]
                let clamped = max(-1, min(1, sample))
                rawData[i * channels + ch] = Int16(clamped * Float(Int16.max))
            }
        }

        rawData.withUnsafeBufferPointer { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
        }

        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * bytesPerSample),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(bytesPerSample * 8),
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        guard let format = formatDesc else { return nil }

        let presentationTime = CMTime(value: Int64(offset), timescale: CMTimeScale(sampleRate))

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: count,
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }

    private static func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Flip for UIImage coordinate system
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return buffer
    }
}
