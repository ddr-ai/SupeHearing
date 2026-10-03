import Foundation
import SwiftUI
import Combine

@MainActor
public final class SeparationViewModel: ObservableObject {
    public var audioFile: AudioFile
    @Published public var quality: SeparationQuality = .balanced
    @Published public var isSeparating: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var currentChunk: Int = 0
    @Published public var totalChunks: Int = 0
    @Published public var statusMessage: String = "Ready to separate"
    @Published public var stems: [Stem: URL] = [:]
    @Published public var playingStem: Stem?
    @Published public var errorMessage: String?

    private var separationTask: Task<Void, Never>?
    private let player = SingleAudioPlayer.shared

    public init(audioFile: AudioFile) {
        self.audioFile = audioFile
        if let existingStems = audioFile.stemURLs {
            self.stems = existingStems
            if !existingStems.isEmpty {
                self.statusMessage = "Stems already extracted"
                self.progress = 1.0
            }
        }
    }

    public var isModelAvailable: Bool {
        SeparationService.shared.isModelAvailable
    }

    public var modelName: String {
        SeparationService.shared.loadedModelName
    }

    public func startSeparation() {
        guard !isSeparating else { return }
        isSeparating = true
        progress = 0.0
        currentChunk = 0
        totalChunks = 0
        statusMessage = "Preparing audio for separation…"

        let inputURL = audioFile.processedURL ?? audioFile.fileURL
        let stemFolder = AudioFile.recordingsDirectory.appendingPathComponent("Stems_\(audioFile.id.uuidString)")

        separationTask = Task {
            do {
                self.statusMessage = "Running \(self.modelName)…"

                let resultStems = try await SeparationService.shared.separateStems(
                    inputURL: inputURL,
                    outputDirectory: stemFolder,
                    quality: self.quality
                ) { [weak self] p, chunk, total in
                    Task { @MainActor [weak self] in
                        self?.progress = p
                        self?.currentChunk = chunk
                        self?.totalChunks = total
                        self?.statusMessage = "Separating chunk \(chunk) of \(total)…"
                    }
                }

                self.stems = resultStems
                self.progress = 1.0
                self.statusMessage = "Separation Complete"
                self.isSeparating = false

                // Update AudioFile model
                var stemNames: [Stem: String] = [:]
                for (stem, url) in resultStems {
                    stemNames[stem] = "Stems_\(self.audioFile.id.uuidString)/\(url.lastPathComponent)"
                }

                self.audioFile.status = .separated
                self.audioFile.stemFileNames = stemNames
                FileListViewModel.shared.update(self.audioFile)
            } catch {
                if Task.isCancelled {
                    self.statusMessage = "Separation Cancelled"
                } else {
                    self.errorMessage = "Separation failed: \(error.localizedDescription)"
                    self.statusMessage = "Error occurred"
                }
                self.isSeparating = false
            }
        }
    }

    public func cancelSeparation() {
        separationTask?.cancel()
        isSeparating = false
        statusMessage = "Separation cancelled"
        progress = 0.0
    }

    public func previewStem(_ stem: Stem) {
        if playingStem == stem {
            player.stop()
            playingStem = nil
        } else {
            guard let url = stems[stem] else { return }
            do {
                try player.load(url: url)
                player.play()
                playingStem = stem
            } catch {
                print("[SeparationViewModel] Stem playback error: \(error)")
            }
        }
    }
}
