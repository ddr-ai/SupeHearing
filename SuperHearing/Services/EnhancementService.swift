import Foundation
import AVFoundation

public protocol EnhancementServiceProtocol: AnyObject, Sendable {
    func enhanceAudio(
        inputURL: URL,
        outputURL: URL,
        intensity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// Offline enhancement service for distant speech intelligibility, adaptive gain control, and dynamic range compression.
public final class EnhancementService: EnhancementServiceProtocol, @unchecked Sendable {
    public static let shared = EnhancementService()

    public init() {}

    public func enhanceAudio(
        inputURL: URL,
        outputURL: URL,
        intensity: Float = 1.0,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "EnhancementService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate audio buffer"])
        }

        try audioFile.read(into: pcmBuffer)
        guard let channelData = pcmBuffer.floatChannelData?[0] else {
            throw NSError(domain: "EnhancementService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio is not float PCM"])
        }

        progress(0.2)

        let totalSamples = Int(frameCount)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: totalSamples))

        let sampleRate = Float(format.sampleRate)
        let agc = AGCProcessor(sampleRate: sampleRate, targetDBFS: -18.0)

        progress(0.4)

        // Process distant sound enhancement
        let enhancedSamples = agc.process(samples: samples, enhancementIntensity: intensity)

        progress(0.8)

        // Write output audio file
        outputURL.removeIfExisting()

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(enhancedSamples.count)) else {
            throw NSError(domain: "EnhancementService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
        }
        outputBuffer.frameLength = AVAudioFrameCount(enhancedSamples.count)

        if let outChannel = outputBuffer.floatChannelData?[0] {
            enhancedSamples.withUnsafeBufferPointer { ptr in
                outChannel.initialize(from: ptr.baseAddress!, count: enhancedSamples.count)
            }
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: audioFile.fileFormat.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try outputFile.write(from: outputBuffer)

        progress(1.0)
    }
}
