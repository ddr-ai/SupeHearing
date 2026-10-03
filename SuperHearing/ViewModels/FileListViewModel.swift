import Foundation
import SwiftUI
import Combine

public enum FileFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case raw = "Raw"
    case processed = "Processed"
    case separated = "Separated"

    public var id: String { rawValue }
}

@MainActor
public final class FileListViewModel: ObservableObject {
    public static let shared = FileListViewModel()

    @Published public var files: [AudioFile] = []
    @Published public var selectedFilter: FileFilter = .all
    @Published public var playingFileID: UUID?
    @Published public var isPlaying: Bool = false
    @Published public var playbackProgress: Double = 0.0

    private let player = SingleAudioPlayer.shared
    private var playerTimer: Timer?

    private var metadataURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("recordings_meta.json")
    }

    public init() {
        loadFiles()
    }

    public var filteredFiles: [AudioFile] {
        switch selectedFilter {
        case .all:
            return files
        case .raw:
            return files.filter { $0.status == .raw }
        case .processed:
            return files.filter { $0.status == .processed }
        case .separated:
            return files.filter { $0.status == .separated }
        }
    }

    public func loadFiles() {
        if FileManager.default.fileExists(atPath: metadataURL.path),
           let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode([AudioFile].self, from: data) {
            self.files = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            self.files = []
        }
    }

    public func saveFiles() {
        if let data = try? JSONEncoder().encode(files) {
            try? data.write(to: metadataURL)
        }
    }

    public func add(_ file: AudioFile) {
        files.insert(file, at: 0)
        saveFiles()
    }

    public func update(_ file: AudioFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            files[index] = file
            saveFiles()
        }
    }

    public func delete(file: AudioFile) {
        if playingFileID == file.id {
            stopPlayback()
        }

        // Delete raw audio file
        file.fileURL.removeIfExisting()

        // Delete processed audio file
        file.processedURL?.removeIfExisting()

        // Delete stems
        if let stems = file.stemURLs {
            for (_, url) in stems {
                url.removeIfExisting()
            }
        }

        files.removeAll { $0.id == file.id }
        saveFiles()
    }

    public func togglePlayback(for file: AudioFile) {
        if playingFileID == file.id && isPlaying {
            pausePlayback()
        } else if playingFileID == file.id && !isPlaying {
            resumePlayback()
        } else {
            play(file: file)
        }
    }

    private func play(file: AudioFile) {
        stopPlayback()
        let urlToPlay = file.processedURL ?? file.fileURL
        do {
            try player.load(url: urlToPlay)
            player.play()
            playingFileID = file.id
            isPlaying = true
            startPlayerTimer()
        } catch {
            print("[FileListViewModel] Playback error: \(error)")
        }
    }

    public func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    public func resumePlayback() {
        player.play()
        isPlaying = true
    }

    public func stopPlayback() {
        player.stop()
        playingFileID = nil
        isPlaying = false
        playbackProgress = 0.0
        stopPlayerTimer()
    }

    private func startPlayerTimer() {
        stopPlayerTimer()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.player.duration > 0 {
                    self.playbackProgress = self.player.currentTime / self.player.duration
                }
                if !self.player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.playingFileID = nil
                }
            }
        }
    }

    private func stopPlayerTimer() {
        playerTimer?.invalidate()
        playerTimer = nil
    }
}
