import Foundation
import AVFoundation
import Accelerate

public protocol VoiceIsolationServiceProtocol: AnyObject, Sendable {
    func isolateVoice(
        inputURL: URL,
        outputURL: URL,
        strength: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// Offline voice isolation. Keeps harmonic speech and attenuates background that is not speech.
/// This does not separate two people talking at the same time.
public final class VoiceIsolationService: VoiceIsolationServiceProtocol, @unchecked Sendable {
    public static let shared = VoiceIsolationService()

    public init() {}

    public func isolateVoice(
        inputURL: URL,
        outputURL: URL,
        strength: Float = 0.8,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "VoiceIsolationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio"])
        }

        try audioFile.read(into: pcmBuffer)
        guard let channelData = pcmBuffer.floatChannelData?[0] else {
            throw NSError(domain: "VoiceIsolationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio is not float PCM"])
        }

        let totalSamples = Int(frameCount)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: totalSamples))
        let sampleRate = Float(format.sampleRate)
        progress(0.08)

        if Task.isCancelled { throw CancellationError() }

        let isolated = await Task.detached(priority: .userInitiated) {
            self.isolate(samples: samples, sampleRate: sampleRate, strength: strength)
        }.value

        if Task.isCancelled { throw CancellationError() }
        progress(0.86)

        outputURL.removeIfExisting()

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(isolated.count)) else {
            throw NSError(domain: "VoiceIsolationService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
        }
        outputBuffer.frameLength = AVAudioFrameCount(isolated.count)
        if let outChannel = outputBuffer.floatChannelData?[0] {
            isolated.withUnsafeBufferPointer { ptr in
                outChannel.initialize(from: ptr.baseAddress!, count: isolated.count)
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

    /// Returns a copy of `samples` with non-speech background attenuated.
    /// `strength` is 0 (bypass) through 1 (strongest).
    public func isolate(samples: [Float], sampleRate: Float, strength: Float) -> [Float] {
        let amount = strength.clamped(to: 0...1)
        if amount < 0.01 || samples.count < 1024 || sampleRate < 8000 {
            return samples
        }
        guard let stft = STFTProcessor(frameSize: 1024, hopSize: 256) else {
            return samples
        }

        let frames = stft.forward(samples: samples)
        guard frames.count > 4 else { return samples }

        let bins = frames[0].magnitudes.count
        let binHz = sampleRate / Float(stft.frameSize)

        var likelihoods = [Float](repeating: 0, count: frames.count)
        var noiseSum = [Float](repeating: 0, count: bins)
        var meanSum = [Float](repeating: 0, count: bins)
        var noiseFrames: Float = 0

        for (index, frame) in frames.enumerated() {
            let likelihood = speechLikelihood(magnitudes: frame.magnitudes, binHz: binHz)
            likelihoods[index] = likelihood
            let mags = frame.magnitudes
            for k in 0..<bins {
                meanSum[k] += mags[k]
            }
            if likelihood < 0.38 {
                noiseFrames += 1
                for k in 0..<bins {
                    noiseSum[k] += mags[k]
                }
            }
        }

        var noise = [Float](repeating: 0, count: bins)
        if noiseFrames >= Float(frames.count) * 0.08 {
            let scale = 1 / noiseFrames
            for k in 0..<bins {
                noise[k] = max(noiseSum[k] * scale, 1e-7)
            }
        } else {
            let scale = 0.35 / Float(frames.count)
            for k in 0..<bins {
                noise[k] = max(meanSum[k] * scale, 1e-7)
            }
        }

        var presence = [Float](repeating: 0, count: frames.count)
        var envelope: Float = 0
        for index in 0..<frames.count {
            let raw = likelihoods[index]
            if raw > envelope {
                envelope = raw
            } else {
                envelope = envelope * 0.94 + raw * 0.06
            }
            presence[index] = max(raw, envelope)
        }

        let minGain = 0.035 + (1 - amount) * 0.5
        let oversub = 0.5 + amount * 1.6
        var previousGain = [Float](repeating: minGain, count: bins)
        var processed: [STFTProcessor.SpectralFrame] = []
        processed.reserveCapacity(frames.count)

        for (index, frame) in frames.enumerated() {
            let speech = (((presence[index] - 0.40) / 0.30)).clamped(to: 0...1)
            var gains = [Float](repeating: minGain, count: bins)
            let mags = frame.magnitudes

            for k in 0..<bins {
                let freq = Float(k) * binHz
                let noiseLevel = noise[k]
                let signal = max(0, mags[k] - noiseLevel)
                let snr = signal / (noiseLevel + 1e-8)
                let wiener = snr / (snr + oversub)
                var gain = speech * wiener + (1 - speech) * minGain

                if freq < 120 {
                    gain *= 0.12 + (1 - amount) * 0.5
                } else if freq > 8000 {
                    gain *= 0.18 + (1 - amount) * 0.45
                } else if freq > 4500 {
                    gain *= 0.3 + 0.7 * speech
                }

                gains[k] = gain.clamped(to: 0...1)
            }

            if bins > 2 {
                var smoothed = gains
                for k in 1..<(bins - 1) {
                    smoothed[k] = 0.25 * gains[k - 1] + 0.5 * gains[k] + 0.25 * gains[k + 1]
                }
                gains = smoothed
            }

            for k in 0..<bins {
                let gain = (0.4 * previousGain[k] + 0.6 * gains[k]).clamped(to: 0...1)
                gains[k] = gain
                previousGain[k] = gain
            }

            var real = frame.real
            var imag = frame.imag
            var outMags = mags
            for k in 0..<bins {
                real[k] *= gains[k]
                imag[k] *= gains[k]
                outMags[k] *= gains[k]
            }
            processed.append(STFTProcessor.SpectralFrame(
                real: real,
                imag: imag,
                magnitudes: outMags,
                phases: frame.phases
            ))
        }

        return stft.inverse(frames: processed, targetLength: samples.count)
    }

    /// 0 = not speech, 1 = harmonic energy sitting in the speech band.
    private func speechLikelihood(magnitudes: [Float], binHz: Float) -> Float {
        guard magnitudes.count > 8, binHz > 0 else { return 0 }

        var speech: Float = 0
        var total: Float = 0
        var logSum: Float = 0
        let count = magnitudes.count

        for k in 1..<count {
            let mag = magnitudes[k]
            let freq = Float(k) * binHz
            total += mag
            logSum += log(mag + 1e-10)
            if freq >= 250 && freq <= 3600 {
                speech += mag
            }
        }

        let band = speech / (total + 1e-8)
        let n = Float(count - 1)
        let flatness = exp(logSum / n) / ((total / n) + 1e-10)
        let tonal = (1 - min(1, flatness * 5)).clamped(to: 0...1)
        let harmonic = harmonicScore(magnitudes: magnitudes, binHz: binHz)

        let combined = 0.5 * harmonic + 0.3 * band + 0.2 * tonal
        return combined.clamped(to: 0...1)
    }

    private func harmonicScore(magnitudes: [Float], binHz: Float) -> Float {
        let minBin = max(1, Int(80 / binHz))
        let maxBin = min(magnitudes.count - 2, Int(400 / binHz))
        guard maxBin > minBin else { return 0 }

        var peakBin = minBin
        var peak: Float = 0
        for k in minBin...maxBin where magnitudes[k] > peak {
            peak = magnitudes[k]
            peakBin = k
        }
        guard peak > 1e-6 else { return 0 }

        var score: Float = 0
        var harmonics: Float = 0
        for h in 2...5 {
            let bin = peakBin * h
            if bin <= 0 || bin >= magnitudes.count - 1 { break }
            let neighbor = (magnitudes[bin - 1] + magnitudes[bin + 1]) * 0.5
            let ratio = magnitudes[bin] / (neighbor + 1e-8)
            score += min(3, ratio)
            harmonics += 1
        }
        guard harmonics > 0 else { return 0 }
        return min(1, (score / harmonics) / 2)
    }
}
