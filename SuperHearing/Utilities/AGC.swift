import Foundation
import Accelerate

/// Biquad IIR filter coefficients for parametric EQ, low-cut, and shelves.
public struct BiquadFilter: Sendable {
    public var b0: Float = 1.0
    public var b1: Float = 0.0
    public var b2: Float = 0.0
    public var a1: Float = 0.0
    public var a2: Float = 0.0

    public static func highPass(frequency: Float, sampleRate: Float, q: Float = 0.707) -> BiquadFilter {
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * q)
        let cosw = cos(omega)

        let a0 = 1.0 + alpha
        let b0 = ((1.0 + cosw) / 2.0) / a0
        let b1 = (-(1.0 + cosw)) / a0
        let b2 = ((1.0 + cosw) / 2.0) / a0
        let a1 = (-2.0 * cosw) / a0
        let a2 = (1.0 - alpha) / a0

        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    public static func peaking(frequency: Float, gainDB: Float, sampleRate: Float, q: Float = 1.2) -> BiquadFilter {
        let a = pow(10.0, gainDB / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * q)
        let cosw = cos(omega)

        let a0 = 1.0 + alpha / a
        let b0 = (1.0 + alpha * a) / a0
        let b1 = (-2.0 * cosw) / a0
        let b2 = (1.0 - alpha * a) / a0
        let a1 = (-2.0 * cosw) / a0
        let a2 = (1.0 - alpha / a) / a0

        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    public static func highShelf(frequency: Float, gainDB: Float, sampleRate: Float) -> BiquadFilter {
        let a = pow(10.0, gainDB / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let alpha = sin(omega) / 2.0 * sqrt(2.0)
        let cosw = cos(omega)
        let twoSqrtAAlpha = 2.0 * sqrt(a) * alpha

        let a0 = (a + 1.0) - (a - 1.0) * cosw + twoSqrtAAlpha
        let b0 = (a * ((a + 1.0) + (a - 1.0) * cosw + twoSqrtAAlpha)) / a0
        let b1 = (-2.0 * a * ((a - 1.0) + (a + 1.0) * cosw)) / a0
        let b2 = (a * ((a + 1.0) + (a - 1.0) * cosw - twoSqrtAAlpha)) / a0
        let a1 = (2.0 * ((a - 1.0) - (a + 1.0) * cosw)) / a0
        let a2 = ((a + 1.0) - (a - 1.0) * cosw - twoSqrtAAlpha) / a0

        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    public func apply(to samples: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0

        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            output[i] = y0

            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return output
    }
}

/// Adaptive Gain Control (AGC), Multiband Equalization, and Peak Limiting for distant sound enhancement.
public final class AGCProcessor: Sendable {
    public let sampleRate: Float
    public let targetRMS: Float // Target RMS in linear amplitude (-18 dBFS = ~0.126)
    public let maxGain: Float   // Maximum gain boost factor (e.g. 18dB = ~8.0)
    public let minGain: Float   // Minimum gain factor (e.g. -6dB = ~0.5)

    public init(
        sampleRate: Float = 48000.0,
        targetDBFS: Float = -18.0,
        maxGainDB: Float = 24.0,
        minGainDB: Float = -6.0
    ) {
        self.sampleRate = sampleRate
        self.targetRMS = pow(10.0, targetDBFS / 20.0)
        self.maxGain = pow(10.0, maxGainDB / 20.0)
        self.minGain = pow(10.0, minGainDB / 20.0)
    }

    /// Enhances distant sounds and speech: applies low-cut, presence equalization, AGC, compression, and limiting.
    public func process(samples: [Float], enhancementIntensity: Float = 1.0) -> [Float] {
        guard !samples.isEmpty else { return [] }

        // 1. High-pass filter at 90Hz to strip rumble & handling noise
        let hpf = BiquadFilter.highPass(frequency: 90.0, sampleRate: sampleRate)
        var filtered = hpf.apply(to: samples)

        // 2. Presence peaking filter at 3.2kHz (+5.0 dB scaled by intensity)
        let presenceBoost = 5.0 * enhancementIntensity
        if presenceBoost > 0.1 {
            let presenceEq = BiquadFilter.peaking(frequency: 3200.0, gainDB: presenceBoost, sampleRate: sampleRate, q: 1.2)
            filtered = presenceEq.apply(to: filtered)
        }

        // 3. High-shelf filter at 6.5kHz (+3.0 dB scaled by intensity) for consonant sparkle
        let airBoost = 3.0 * enhancementIntensity
        if airBoost > 0.1 {
            let airEq = BiquadFilter.highShelf(frequency: 6500.0, gainDB: airBoost, sampleRate: sampleRate)
            filtered = airEq.apply(to: filtered)
        }

        // 4. Adaptive Gain Control with smoothed envelope
        let windowSamples = Int(sampleRate * 0.05) // 50ms window
        let attackCoef = exp(-1.0 / (sampleRate * 0.010)) // 10ms attack
        let releaseCoef = exp(-1.0 / (sampleRate * 0.150)) // 150ms release

        var currentGain: Float = 1.0
        var currentEnv: Float = 0.0
        var agcOutput = [Float](repeating: 0, count: filtered.count)

        for i in 0..<filtered.count {
            let inputAbs = abs(filtered[i])

            // Envelope follower
            if inputAbs > currentEnv {
                currentEnv = attackCoef * currentEnv + (1.0 - attackCoef) * inputAbs
            } else {
                currentEnv = releaseCoef * currentEnv + (1.0 - releaseCoef) * inputAbs
            }

            // Target gain calculation
            let desiredGain: Float
            if currentEnv > 0.001 {
                let rawGain = targetRMS / currentEnv
                desiredGain = max(minGain, min(maxGain, rawGain))
            } else {
                desiredGain = maxGain * 0.5
            }

            // Smooth gain transition
            let blendGain = 1.0 + (desiredGain - 1.0) * enhancementIntensity
            currentGain = 0.999 * currentGain + 0.001 * blendGain

            agcOutput[i] = filtered[i] * currentGain
        }

        // 5. Dynamic Range Compression (Threshold: -24dBFS, Ratio 3:1)
        let compThreshold = pow(10.0, -24.0 / 20.0) // ~0.063
        let ratio: Float = 3.0

        for i in 0..<agcOutput.count {
            let val = agcOutput[i]
            let absVal = abs(val)
            if absVal > compThreshold {
                let over = absVal - compThreshold
                let compressed = compThreshold + (over / ratio)
                agcOutput[i] = (val / absVal) * compressed
            }
        }

        // 6. Soft-knee peak limiter at -1.0 dBFS (0.891 ceiling)
        let ceiling: Float = 0.891
        for i in 0..<agcOutput.count {
            let val = agcOutput[i]
            let absVal = abs(val)
            if absVal > ceiling {
                // Soft saturation curve: ceiling + (1 - ceiling) * tanh((abs - ceiling) / (1 - ceiling))
                let delta = absVal - ceiling
                let headroom = 1.0 - ceiling
                let compressedPeak = ceiling + headroom * tanh(delta / headroom)
                agcOutput[i] = (val / absVal) * min(0.99, compressedPeak)
            }
        }

        return agcOutput
    }
}
