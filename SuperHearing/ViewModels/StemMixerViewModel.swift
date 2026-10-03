import Foundation
import SwiftUI
import Combine

@MainActor
public final class StemMixerViewModel: ObservableObject {
    public let stemURLs: [Stem: URL]
    private let mixer = StemMixerEngine()

    @Published public var gains: [Stem: Float] = [
        .vocals: 1.0,
        .drums: 1.0,
        .bass: 1.0,
        .other: 1.0
    ]

    @Published public var pans: [Stem: Float] = [
        .vocals: 0.0,
        .drums: 0.0,
        .bass: 0.0,
        .other: 0.0
    ]

    @Published public var soloedStems: Set<Stem> = []
    @Published public var mutedStems: Set<Stem> = []
    @Published public var masterVolume: Float = 1.0

    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0.0
    @Published public var duration: TimeInterval = 0.0
    @Published public var loopEnabled: Bool = false

    @Published public var isExporting: Bool = false
    @Published public var exportedMixURL: URL?
    @Published public var exportMessage: String?

    private var timer: Timer?

    public init(stemURLs: [Stem: URL]) {
        self.stemURLs = stemURLs
        setupMixer()
    }

    deinit {
        mixer.stop()
        timer?.invalidate()
    }

    private func setupMixer() {
        do {
            try mixer.loadStems(stemURLs)
            self.duration = mixer.duration
            startTimer()
        } catch {
            print("[StemMixerViewModel] Failed to load stems into mixer: \(error)")
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            mixer.pause()
            isPlaying = false
        } else {
            mixer.play()
            isPlaying = true
        }
    }

    public func seek(to time: TimeInterval) {
        mixer.seek(to: time)
        currentTime = time
    }

    public func setGain(stem: Stem, gain: Float) {
        gains[stem] = gain
        mixer.setVolume(stem: stem, volume: gain)
    }

    public func setPan(stem: Stem, pan: Float) {
        pans[stem] = pan
        mixer.setPan(stem: stem, pan: pan)
    }

    public func toggleSolo(stem: Stem) {
        mixer.toggleSolo(stem: stem)
        soloedStems = mixer.soloedStems
    }

    public func toggleMute(stem: Stem) {
        mixer.toggleMute(stem: stem)
        mutedStems = mixer.mutedStems
    }

    public func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        mixer.setMasterVolume(volume)
    }

    public func toggleLoop() {
        loopEnabled.toggle()
        mixer.loopEnabled = loopEnabled
    }

    public func exportMix() {
        isExporting = true
        exportMessage = "Rendering master mix…"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let exportName = "Mix_\(timestamp).caf"
        let targetURL = AudioFile.recordingsDirectory.appendingPathComponent(exportName)

        Task.detached { [mixer] in
            do {
                try mixer.exportMix(to: targetURL)
                await MainActor.run {
                    self.exportedMixURL = targetURL
                    self.isExporting = false
                    self.exportMessage = "Mix saved as \(exportName)"

                    // Add to library
                    let newAudio = AudioFile(
                        title: "Master Mix \(timestamp)",
                        createdAt: Date(),
                        duration: mixer.duration,
                        fileName: exportName,
                        fileSize: targetURL.fileSize,
                        status: .processed
                    )
                    FileListViewModel.shared.add(newAudio)
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = self.mixer.currentTime
                self.isPlaying = self.mixer.isPlaying
            }
        }
    }
}
