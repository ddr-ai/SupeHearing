import Foundation
import Accelerate

/// Thread-safe circular buffer for streaming audio samples, calculating real-time RMS, and downsampling waveforms.
public final class CircularAudioBuffer: @unchecked Sendable {
    private let capacity: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    public init(capacity: Int = 48000) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Appends audio samples into the circular buffer.
    public func append(samples: UnsafePointer<Float>, count sampleCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        for i in 0..<sampleCount {
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }

    /// Appends an array of float samples.
    public func append(contentsOf samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            if let baseAddress = ptr.baseAddress {
                append(samples: baseAddress, count: ptr.count)
            }
        }
    }

    /// Computes the current Root Mean Square (RMS) value of the latest window.
    public func currentRMS(windowSize: Int = 1024) -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard count > 0 else { return 0.0 }
        let effectiveWindow = min(windowSize, count)
        var sumSquares: Float = 0.0

        for i in 0..<effectiveWindow {
            var index = (writeIndex - 1 - i) % capacity
            if index < 0 { index += capacity }
            let val = buffer[index]
            sumSquares += val * val
        }

        return sqrt(sumSquares / Float(effectiveWindow))
    }

    /// Converts RMS to dBFS. Silence or 0 yields -100 dBFS.
    public static func toDbFS(rms: Float) -> Float {
        guard rms > 0.00001 else { return -100.0 }
        let db = 20.0 * log10(rms)
        return max(-100.0, min(0.0, db))
    }

    /// Returns the most recent samples in chronological order up to sampleCount.
    public func latestSamples(count requestedCount: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let n = min(requestedCount, count)
        guard n > 0 else { return [] }

        var result = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var index = (writeIndex - n + i) % capacity
            if index < 0 { index += capacity }
            result[i] = buffer[index]
        }
        return result
    }

    /// Downsamples a slice of samples into a target count of points normalized between 0.0 and 1.0 for waveform display.
    public static func downsample(samples: [Float], targetPoints: Int) -> [Float] {
        guard !samples.isEmpty, targetPoints > 0 else {
            return [Float](repeating: 0.05, count: max(1, targetPoints))
        }

        if samples.count <= targetPoints {
            return samples.map { min(1.0, max(0.05, abs($0))) }
        }

        var result = [Float]()
        result.reserveCapacity(targetPoints)
        let chunkSize = samples.count / targetPoints

        for i in 0..<targetPoints {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            var maxVal: Float = 0.0
            for j in start..<end {
                let absVal = abs(samples[j])
                if absVal > maxVal { maxVal = absVal }
            }
            result.append(max(0.05, min(1.0, maxVal)))
        }

        return result
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer = [Float](repeating: 0, count: capacity)
        writeIndex = 0
        count = 0
    }
}
