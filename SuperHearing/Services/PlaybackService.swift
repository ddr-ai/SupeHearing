import Foundation
import AVFoundation

public protocol PlaybackServiceProtocol: AnyObject, Sendable {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }

    func load(url: URL) throws
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func stop()
}

/// Plays a single audio file with scrubbing and time observation.
public final class SingleAudioPlayer: NSObject, PlaybackServiceProtocol, AVAudioPlayerDelegate, @unchecked Sendable {
    public static let shared = SingleAudioPlayer()

    private var player: AVAudioPlayer?
    private var timer: Timer?

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0.0
    public private(set) var duration: TimeInterval = 0.0
    public var onPlaybackEnded: (@Sendable () -> Void)?

    public override init() {
        super.init()
    }

    deinit {
        stopTimer()
    }

    public func load(url: URL) throws {
        stop()
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        self.player = audioPlayer
        self.duration = audioPlayer.duration
        self.currentTime = 0.0
    }

    public func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    public func seek(to time: TimeInterval) {
        guard let player = player else { return }
        player.currentTime = min(max(0, time), duration)
        currentTime = player.currentTime
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0.0
        duration = 0.0
        stopTimer()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0.0
        stopTimer()
        onPlaybackEnded?()
    }

    private func startTimer() {
        stopTimer()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
}

/// Synchronized 4-stem mixer playback engine using AVAudioEngine and AVAudioPlayerNodes.
public final class StemMixerEngine: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var playerNodes: [Stem: AVAudioPlayerNode] = [:]
    private var audioFiles: [Stem: AVAudioFile] = [:]
    private var stemBuffers: [Stem: AVAudioPCMBuffer] = [:]

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0.0
    public private(set) var duration: TimeInterval = 0.0
    public var loopEnabled: Bool = false

    public var volumes: [Stem: Float] = [
        .vocals: 1.0,
        .drums: 1.0,
        .bass: 1.0,
        .other: 1.0
    ]

    public var pans: [Stem: Float] = [
        .vocals: 0.0,
        .drums: 0.0,
        .bass: 0.0,
        .other: 0.0
    ]

    public var soloedStems: Set<Stem> = []
    public var mutedStems: Set<Stem> = []
    public var masterVolume: Float = 1.0

    private var timer: Timer?
    private var startPlaybackHostTime: UInt64 = 0
    private var seekOffsetTime: TimeInterval = 0.0

    public init() {
        setupNodes()
    }

    deinit {
        stop()
    }

    private func setupNodes() {
        for stem in Stem.allCases {
            let node = AVAudioPlayerNode()
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: nil)
            playerNodes[stem] = node
        }
    }

    /// Loads 4 stems into memory buffers for sample-accurate synchronization.
    public func loadStems(_ stemURLs: [Stem: URL]) throws {
        stop()

        var maxDuration: TimeInterval = 0.0

        for (stem, url) in stemURLs {
            let file = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                continue
            }
            try file.read(into: buffer)

            audioFiles[stem] = file
            stemBuffers[stem] = buffer

            let d = Double(frameCount) / file.processingFormat.sampleRate
            if d > maxDuration { maxDuration = d }
        }

        self.duration = maxDuration
        self.currentTime = 0.0
        self.seekOffsetTime = 0.0

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        applyMixerSettings()
    }

    public func play() {
        guard !isPlaying, duration > 0 else { return }

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("[StemMixerEngine] Engine start error: \(error)")
            return
        }

        for (stem, node) in playerNodes {
            guard let buffer = stemBuffers[stem] else { continue }
            node.stop()

            // Calculate starting sample frame based on seekOffsetTime
            let sampleRate = buffer.format.sampleRate
            let startFrame = AVAudioFramePosition(seekOffsetTime * sampleRate)

            if startFrame < AVAudioFramePosition(buffer.frameLength) {
                let remainingFrames = AVAudioFrameCount(AVAudioFramePosition(buffer.frameLength) - startFrame)
                if let subBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remainingFrames) {
                    subBuffer.frameLength = remainingFrames
                    let channelCount = Int(buffer.format.channelCount)
                    for ch in 0..<channelCount {
                        if let src = buffer.floatChannelData?[ch],
                           let dst = subBuffer.floatChannelData?[ch] {
                            let srcOffset = src.advanced(by: Int(startFrame))
                            dst.initialize(from: srcOffset, count: Int(remainingFrames))
                        }
                    }

                    node.scheduleBuffer(subBuffer, at: nil, options: loopEnabled ? .loops : []) { [weak self] in
                        // Handled by timer check
                    }
                }
            }
            node.play()
        }

        isPlaying = true
        startPlaybackHostTime = mach_absolute_time()
        startTimer()
    }

    public func pause() {
        guard isPlaying else { return }
        for (_, node) in playerNodes {
            node.pause()
        }
        isPlaying = false
        stopTimer()
    }

    public func stop() {
        stopTimer()
        for (_, node) in playerNodes {
            node.stop()
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isPlaying = false
        currentTime = 0.0
        seekOffsetTime = 0.0
    }

    public func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        seekOffsetTime = clamped
        currentTime = clamped

        if isPlaying {
            pause()
            play()
        }
    }

    public func setVolume(stem: Stem, volume: Float) {
        volumes[stem] = volume
        applyMixerSettings()
    }

    public func setPan(stem: Stem, pan: Float) {
        pans[stem] = pan
        applyMixerSettings()
    }

    public func toggleSolo(stem: Stem) {
        if soloedStems.contains(stem) {
            soloedStems.remove(stem)
        } else {
            soloedStems.insert(stem)
        }
        applyMixerSettings()
    }

    public func toggleMute(stem: Stem) {
        if mutedStems.contains(stem) {
            mutedStems.remove(stem)
        } else {
            mutedStems.insert(stem)
        }
        applyMixerSettings()
    }

    public func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        applyMixerSettings()
    }

    public func applyMixerSettings() {
        let hasSolo = !soloedStems.isEmpty

        for stem in Stem.allCases {
            guard let node = playerNodes[stem] else { continue }

            let isMuted = mutedStems.contains(stem)
            let isSoloed = soloedStems.contains(stem)

            var effectiveGain: Float = volumes[stem] ?? 1.0

            if isMuted {
                effectiveGain = 0.0
            } else if hasSolo && !isSoloed {
                effectiveGain = 0.0
            }

            node.volume = effectiveGain * masterVolume
            node.pan = pans[stem] ?? 0.0
        }
    }

    /// Renders the current mix to a standalone audio file on disk.
    public func exportMix(to destinationURL: URL) throws {
        destinationURL.removeIfExisting()

        guard let firstBuffer = stemBuffers.values.first else {
            throw NSError(domain: "StemMixerEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No stem buffers loaded"])
        }

        let frameCount = firstBuffer.frameLength
        let format = firstBuffer.format

        guard let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "StemMixerEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create mix buffer"])
        }
        mixBuffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            guard let mixChannel = mixBuffer.floatChannelData?[ch] else { continue }
            // Clear
            mixChannel.initialize(repeating: 0, count: Int(frameCount))

            let hasSolo = !soloedStems.isEmpty
            for (stem, buffer) in stemBuffers {
                let isMuted = mutedStems.contains(stem)
                let isSoloed = soloedStems.contains(stem)

                var gain = volumes[stem] ?? 1.0
                if isMuted || (hasSolo && !isSoloed) {
                    gain = 0.0
                }

                gain *= masterVolume
                if gain > 0.001, let stemChannel = buffer.floatChannelData?[min(ch, Int(buffer.format.channelCount) - 1)] {
                    for i in 0..<Int(frameCount) {
                        mixChannel[i] += stemChannel[i] * gain
                    }
                }
            }

            // Soft clamp to prevent digital clipping
            for i in 0..<Int(frameCount) {
                mixChannel[i] = max(-0.99, min(0.99, mixChannel[i]))
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        let outFile = try AVAudioFile(forWriting: destinationURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try outFile.write(from: mixBuffer)
    }

    private func startTimer() {
        stopTimer()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentTime += 0.05
                if self.currentTime >= self.duration {
                    if self.loopEnabled {
                        self.seek(to: 0)
                    } else {
                        self.pause()
                        self.currentTime = self.duration
                    }
                }
            }
        }
    }

    private func stopTimer() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
}
