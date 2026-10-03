import Foundation
import AVFoundation
import Accelerate

public protocol NoiseReductionServiceProtocol: AnyObject, Sendable {
    func reduceNoise(
        inputURL: URL,
        outputURL: URL,
        strength: Float,
        useWiener: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// Offline spectral noise reduction service using Apple Accelerate STFT, spectral gating, and Wiener filtering.
public final class NoiseReductionService: NoiseReductionServiceProtocol, @unchecked Sendable {
    public static let shared = NoiseReductionService()

    public init() {}

    public func reduceNoise(
        inputURL: URL,
        outputURL: URL,
        strength: Float = 1.5,
        useWiener: Bool = true,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Read input audio file
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "NoiseReductionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate audio buffer"])
        }

        try audioFile.read(into: pcmBuffer)
        guard let channelData = pcmBuffer.floatChannelData?[0] else {
            throw NSError(domain: "NoiseReductionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio is not float PCM"])
        }

        let totalSamples = Int(frameCount)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: totalSamples))

        guard let stft = STFTProcessor(frameSize: 1024, hopSize: 512) else {
            throw NSError(domain: "NoiseReductionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize STFT"])
        }

        progress(0.1)

        // Forward STFT
        var spectralFrames = stft.forward(samples: samples)
        guard !spectralFrames.isEmpty else {
            throw NSError(domain: "NoiseReductionService", code: 4, userInfo: [NSLocalizedDescriptionKey: "No spectral frames generated"])
        }

        progress(0.3)

        // Estimate noise floor profile from first 500ms (or up to first 25 frames)
        let sampleRate = Float(format.sampleRate)
        let noiseFramesCount = max(5, min(25, Int((sampleRate * 0.5) / Float(stft.hopSize))))
        let actualNoiseFrames = min(noiseFramesCount, spectralFrames.count)

        let halfFrame = stft.frameSize / 2
        var noiseFloor = [Float](repeating: 0, count: halfFrame)

        for i in 0..<actualNoiseFrames {
            let mags = spectralFrames[i].magnitudes
            for k in 0..<halfFrame {
                noiseFloor[k] += mags[k]
            }
        }

        for k in 0..<halfFrame {
            noiseFloor[k] /= Float(actualNoiseFrames)
        }

        progress(0.5)

        // Apply spectral gating / Wiener filtering
        let spectralFloor: Float = 0.06 // Prevents musical chirping artifacts
        let eps: Float = 1e-7

        for i in 0..<spectralFrames.count {
            if Task.isCancelled { break }

            var frame = spectralFrames[i]
            for k in 0..<halfFrame {
                let mag = frame.magnitudes[k]
                let noise = noiseFloor[k]
                let gain: Float

                if useWiener {
                    let sigPower = mag * mag
                    let noisePower = noise * noise * strength
                    let ratio = (sigPower - noisePower) / (sigPower + eps)
                    gain = max(spectralFloor, min(1.0, ratio))
                } else {
                    let ratio = 1.0 - (strength * noise / (mag + eps))
                    gain = max(spectralFloor, min(1.0, ratio))
                }

                frame.real[k] *= gain
                frame.imag[k] *= gain
                frame.magnitudes[k] *= gain
            }
            spectralFrames[i] = frame

            if i % 100 == 0 {
                let currentProgress = 0.5 + 0.35 * (Double(i) / Double(spectralFrames.count))
                progress(currentProgress)
            }
        }

        progress(0.85)

        // Inverse STFT with Overlap-Add
        let cleanedSamples = stft.inverse(frames: spectralFrames, targetLength: totalSamples)

        progress(0.95)

        // Write output audio file
        outputURL.removeIfExisting()

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(cleanedSamples.count)) else {
            throw NSError(domain: "NoiseReductionService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
        }
        outputBuffer.frameLength = AVAudioFrameCount(cleanedSamples.count)

        if let outChannel = outputBuffer.floatChannelData?[0] {
            cleanedSamples.withUnsafeBufferPointer { ptr in
                outChannel.initialize(from: ptr.baseAddress!, count: cleanedSamples.count)
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
