import XCTest
@testable import SuperHearing

final class SuperHearingTests: XCTestCase {

    func testCircularAudioBufferRMSAndDBFS() {
        let buffer = CircularAudioBuffer(capacity: 4096)
        XCTAssertEqual(buffer.currentRMS(), 0.0)
        XCTAssertEqual(CircularAudioBuffer.toDbFS(rms: 0.0), -100.0)

        // Fill with constant 0.5 amplitude
        let constantSamples = [Float](repeating: 0.5, count: 1024)
        buffer.append(contentsOf: constantSamples)

        let rms = buffer.currentRMS(windowSize: 1024)
        XCTAssertEqual(rms, 0.5, accuracy: 0.001)

        let dbfs = CircularAudioBuffer.toDbFS(rms: rms)
        // 20 * log10(0.5) = -6.02059 dBFS
        XCTAssertEqual(dbfs, -6.02, accuracy: 0.05)
    }

    func testCircularBufferDownsampling() {
        let testWave = (0..<1000).map { sin(Float($0) * 0.1) }
        let downsampled = CircularAudioBuffer.downsample(samples: testWave, targetPoints: 50)

        XCTAssertEqual(downsampled.count, 50)
        for val in downsampled {
            XCTAssertGreaterThanOrEqual(val, 0.05)
            XCTAssertLessThanOrEqual(val, 1.0)
        }
    }

    func testSTFTForwardAndInverseReconstruction() {
        guard let stft = STFTProcessor(frameSize: 512, hopSize: 256) else {
            XCTFail("Failed to initialize STFTProcessor")
            return
        }

        // Generate 1 second of 440 Hz test sine wave at 48kHz
        let sampleRate: Float = 48000.0
        let totalSamples = 48000
        var testSignal = [Float](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            testSignal[i] = 0.5 * sin(2.0 * Float.pi * 440.0 * Float(i) / sampleRate)
        }

        let spectralFrames = stft.forward(samples: testSignal)
        XCTAssertGreaterThan(spectralFrames.count, 0)

        let reconstructed = stft.inverse(frames: spectralFrames, targetLength: totalSamples)
        XCTAssertEqual(reconstructed.count, totalSamples)

        // Check reconstruction fidelity in the middle section (away from window edges)
        let testRange = 10000..<20000
        var errorSum: Float = 0
        for i in testRange {
            let diff = abs(testSignal[i] - reconstructed[i])
            errorSum += diff
        }
        let meanError = errorSum / Float(testRange.count)
        XCTAssertLessThan(meanError, 0.05, "Reconstruction error must be minimal")
    }

    func testAGCAndLimiter() {
        let agc = AGCProcessor(sampleRate: 48000.0, targetDBFS: -18.0)

        // Signal with very loud peak (+6dB equivalent, > 1.0)
        var hotSignal = [Float](repeating: 0.1, count: 4800)
        hotSignal[100] = 2.5 // Over-ceiling peak
        hotSignal[200] = -3.0

        let processed = agc.process(samples: hotSignal, enhancementIntensity: 1.0)

        // Check limiter ceiling: no sample should exceed 0.99
        for sample in processed {
            XCTAssertLessThanOrEqual(abs(sample), 0.99, "Limiter failed to prevent digital clipping")
        }
    }

    func testStemEnumProperties() {
        XCTAssertEqual(Stem.allCases.count, 4)
        XCTAssertEqual(Stem.vocals.displayName, "Vocals")
        XCTAssertEqual(Stem.drums.displayName, "Drums")
        XCTAssertEqual(Stem.bass.displayName, "Bass")
        XCTAssertEqual(Stem.other.displayName, "Other")

        for stem in Stem.allCases {
            XCTAssertFalse(stem.systemImage.isEmpty)
            XCTAssertFalse(stem.hexColor.isEmpty)
        }
    }

    func testAudioFileModelCodable() throws {
        let file = AudioFile(
            title: "Test File",
            duration: 125.4,
            fileName: "Test.caf",
            fileSize: 1048576,
            format: .caf,
            status: .raw,
            waveformSamples: [0.1, 0.5, 0.8]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(file)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AudioFile.self, from: data)

        XCTAssertEqual(file.id, decoded.id)
        XCTAssertEqual(file.title, decoded.title)
        XCTAssertEqual(file.formattedDuration, "02:05.4")
        XCTAssertEqual(file.waveformSamples, decoded.waveformSamples)
    }
}
