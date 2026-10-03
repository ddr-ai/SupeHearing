import Foundation
import Accelerate

/// Performs Short-Time Fourier Transform (STFT) and Inverse STFT using Apple Accelerate vDSP.
public final class STFTProcessor: @unchecked Sendable {
    public let frameSize: Int // e.g. 1024
    public let hopSize: Int   // e.g. 512 (50% overlap)
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    private let halfFrame: Int

    public init?(frameSize: Int = 1024, hopSize: Int = 512) {
        guard frameSize > 0 && (frameSize & (frameSize - 1)) == 0 else {
            // Must be power of 2
            return nil
        }
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.halfFrame = frameSize / 2
        self.log2n = vDSP_Length(round(log2(Double(frameSize))))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.fftSetup = setup

        // Generate Hann window
        var win = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&win, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        self.window = win
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Represents a single frequency frame with real, imaginary, magnitude, and phase vectors.
    public struct SpectralFrame {
        public var real: [Float] // halfFrame elements
        public var imag: [Float] // halfFrame elements
        public var magnitudes: [Float]
        public var phases: [Float]
    }

    /// Decomposes time-domain audio samples into an array of spectral frames.
    public func forward(samples: [Float]) -> [SpectralFrame] {
        guard samples.count >= frameSize else { return [] }

        var frames: [SpectralFrame] = []
        let numFrames = (samples.count - frameSize) / hopSize + 1
        frames.reserveCapacity(numFrames)

        var windowed = [Float](repeating: 0, count: frameSize)
        var realPart = [Float](repeating: 0, count: halfFrame)
        var imagPart = [Float](repeating: 0, count: halfFrame)

        for frameIdx in 0..<numFrames {
            let start = frameIdx * hopSize
            let slice = Array(samples[start..<(start + frameSize)])

            // Apply Hann window
            vDSP_vmul(slice, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

            // Pack into split complex
            windowed.withUnsafeBytes { rawPtr in
                let complexPtr = rawPtr.bindMemory(to: DSPComplex.self)
                realPart.withUnsafeMutableBufferPointer { rPtr in
                    imagPart.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        vDSP_ctoz(complexPtr.baseAddress!, 2, &split, 1, vDSP_Length(halfFrame))
                    }
                }
            }

            // Perform forward FFT in place
            realPart.withUnsafeMutableBufferPointer { rPtr in
                imagPart.withUnsafeMutableBufferPointer { iPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Scale factor 0.5 for forward vDSP_fft_zrip
            var scale: Float = 0.5
            vDSP_vsmul(realPart, 1, &scale, &realPart, 1, vDSP_Length(halfFrame))
            vDSP_vsmul(imagPart, 1, &scale, &imagPart, 1, vDSP_Length(halfFrame))

            // Calculate magnitudes and phases
            var mags = [Float](repeating: 0, count: halfFrame)
            var phases = [Float](repeating: 0, count: halfFrame)

            for k in 0..<halfFrame {
                let r = realPart[k]
                let i = imagPart[k]
                mags[k] = sqrt(r * r + i * i)
                phases[k] = atan2(i, r)
            }

            frames.append(SpectralFrame(
                real: realPart,
                imag: imagPart,
                magnitudes: mags,
                phases: phases
            ))
        }

        return frames
    }

    /// Reconstructs time-domain audio samples from spectral frames using Inverse FFT and Overlap-Add.
    public func inverse(frames: [SpectralFrame], targetLength: Int) -> [Float] {
        guard !frames.isEmpty else { return [] }

        var output = [Float](repeating: 0, count: targetLength + frameSize)
        var windowSum = [Float](repeating: 0, count: targetLength + frameSize)

        var realPart = [Float](repeating: 0, count: halfFrame)
        var imagPart = [Float](repeating: 0, count: halfFrame)
        var reconstructed = [Float](repeating: 0, count: frameSize)

        for (frameIdx, frame) in frames.enumerated() {
            realPart = frame.real
            imagPart = frame.imag

            // Perform inverse FFT
            realPart.withUnsafeMutableBufferPointer { rPtr in
                imagPart.withUnsafeMutableBufferPointer { iPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                }
            }

            // Unpack complex to real buffer
            reconstructed.withUnsafeMutableBytes { rawPtr in
                let complexPtr = rawPtr.bindMemory(to: DSPComplex.self)
                realPart.withUnsafeMutableBufferPointer { rPtr in
                    imagPart.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        vDSP_ztoc(&split, 1, complexPtr.baseAddress!, 2, vDSP_Length(halfFrame))
                    }
                }
            }

            // Inverse scaling: divide by (2 * frameSize)
            var scale: Float = 1.0 / Float(2 * frameSize)
            vDSP_vsmul(reconstructed, 1, &scale, &reconstructed, 1, vDSP_Length(frameSize))

            // Apply synthesis Hann window
            vDSP_vmul(reconstructed, 1, window, 1, &reconstructed, 1, vDSP_Length(frameSize))

            // Overlap add into output buffer
            let start = frameIdx * hopSize
            for i in 0..<frameSize {
                let outIdx = start + i
                if outIdx < output.count {
                    output[outIdx] += reconstructed[i]
                    windowSum[outIdx] += window[i] * window[i]
                }
            }
        }

        // Normalize by window sum to remove overlap modulation
        for i in 0..<min(targetLength, output.count) {
            if windowSum[i] > 1e-4 {
                output[i] /= windowSum[i]
            }
        }

        return Array(output.prefix(targetLength))
    }
}
