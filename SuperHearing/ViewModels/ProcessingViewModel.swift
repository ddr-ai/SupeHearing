import Foundation
import SwiftUI
import Combine

public enum ProcessingStage: String {
    case idle = "Ready to process"
    case analyzingNoise = "Analyzing stationary noise floor…"
    case reducingNoise = "Applying vDSP spectral gating…"
    case enhancingSpeech = "Enhancing distant speech & dynamics…"
    case saving = "Finalizing clean master file…"
    case completed = "Processing Complete"
    case failed = "Processing Failed"
}

public enum ABComparisonTrack {
    case original
    case processed
}

@MainActor
public final class ProcessingViewModel: ObservableObject {
    public var audioFile: AudioFile
    @Published public var stage: ProcessingStage = .idle
    @Published public var progress: Double = 0.0
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String?

    // Settings
    @Published public var nrStrength: Float = 1.5
    @Published public var enhancementIntensity: Float = 1.0
    @Published public var useWienerFilter: Bool = true

    // A/B Comparison Playback
    @Published public var activeABTrack: ABComparisonTrack = .processed
    @Published public var isPlayingAB: Bool = false
    @Published public var abCurrentTime: TimeInterval = 0.0
    @Published public var abDuration: TimeInterval = 0.0

    private var processedFileURL: URL?
    private let player = SingleAudioPlayer.shared
    private var processingTask: Task<Void, Never>?
    private var timer: Timer?

    public init(audioFile: AudioFile) {
        self.audioFile = audioFile
        self.processedFileURL = audioFile.processedURL
    }

    public var canCompare: Bool {
        processedFileURL != nil && FileManager.default.fileExists(atPath: processedFileURL!.path)
    }

    public func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        stage = .analyzingNoise
        progress = 0.0

        let inputURL = audioFile.fileURL
        let processedName = "Processed_\(audioFile.fileName)"
        let outputURL = AudioFile.recordingsDirectory.appendingPathComponent(processedName)

        processingTask = Task {
            do {
                // Step 1: Spectral Noise Reduction
                self.stage = .reducingNoise
                let intermediateURL = AudioFile.recordingsDirectory.appendingPathComponent("temp_nr_\(audioFile.fileName)")

                try await NoiseReductionService.shared.reduceNoise(
                    inputURL: inputURL,
                    outputURL: intermediateURL,
                    strength: self.nrStrength,
                    useWiener: self.useWienerFilter
                ) { [weak self] p in
                    Task { @MainActor in
                        self?.progress = p * 0.5
                    }
                }

                // Step 2: Distant Speech Enhancement
                self.stage = .enhancingSpeech
                try await EnhancementService.shared.enhanceAudio(
                    inputURL: intermediateURL,
                    outputURL: outputURL,
                    intensity: self.enhancementIntensity
                ) { [weak self] p in
                    Task { @MainActor in
                        self?.progress = 0.5 + p * 0.45
                    }
                }

                // Cleanup intermediate file
                intermediateURL.removeIfExisting()

                self.stage = .saving
                self.progress = 0.98

                // Update AudioFile model
                self.audioFile.status = .processed
                self.audioFile.processedFileName = processedName
                self.processedFileURL = outputURL

                FileListViewModel.shared.update(self.audioFile)

                self.progress = 1.0
                self.stage = .completed
                self.isProcessing = false

                // Prepare processed playback
                self.activeABTrack = .processed
                self.loadABPlayer()
            } catch {
                if Task.isCancelled {
                    self.stage = .idle
                } else {
                    self.errorMessage = "Failed: \(error.localizedDescription)"
                    self.stage = .failed
                }
                self.isProcessing = false
            }
        }
    }

    public func cancelProcessing() {
        processingTask?.cancel()
        isProcessing = false
        stage = .idle
        progress = 0.0
    }

    // MARK: - A/B Comparison Controls

    public func selectABTrack(_ track: ABComparisonTrack) {
        guard track != activeABTrack else { return }
        let currentPos = player.currentTime
        let wasPlaying = isPlayingAB

        activeABTrack = track
        loadABPlayer()

        player.seek(to: currentPos)
        if wasPlaying {
            player.play()
        }
    }

    public func toggleABPlayback() {
        if isPlayingAB {
            player.pause()
            isPlayingAB = false
            stopTimer()
        } else {
            loadABPlayer()
            player.play()
            isPlayingAB = true
            startTimer()
        }
    }

    private func loadABPlayer() {
        let url: URL?
        switch activeABTrack {
        case .original:
            url = audioFile.fileURL
        case .processed:
            url = processedFileURL ?? audioFile.fileURL
        }

        guard let targetURL = url, FileManager.default.fileExists(atPath: targetURL.path) else { return }

        try? player.load(url: targetURL)
        abDuration = player.duration
        abCurrentTime = player.currentTime
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.abCurrentTime = self.player.currentTime
                if !self.player.isPlaying && self.isPlayingAB {
                    self.isPlayingAB = false
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
