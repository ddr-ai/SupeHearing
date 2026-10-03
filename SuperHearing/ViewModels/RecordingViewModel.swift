import Foundation
import SwiftUI
import Combine

public enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing
    case ready(AudioFile)
}

@MainActor
public final class RecordingViewModel: ObservableObject {
    @Published public var state: RecordingState = .idle
    @Published public var currentDuration: TimeInterval = 0.0
    @Published public var currentAmplitude: Float = 0.0
    @Published public var currentDBFS: Float = -100.0
    @Published public var bluetoothDeviceName: String?
    @Published public var liveWaveform: [Float] = [Float](repeating: 0.05, count: 40)

    // Quick settings
    @Published public var autoNoiseReduction: Bool = false
    @Published public var autoEnhancement: Bool = false

    @Published public var errorMessage: String?
    @Published public var showError: Bool = false

    private let recordingService: RecordingServiceProtocol
    private var timer: Timer?

    public init(recordingService: RecordingServiceProtocol = RecordingService.shared) {
        self.recordingService = recordingService
        self.bluetoothDeviceName = recordingService.connectedBluetoothDevice
    }

    public func toggleRecording() {
        switch state {
        case .idle, .ready:
            startRecording()
        case .recording:
            stopRecording()
        case .paused:
            resumeRecording()
        case .processing:
            break
        }
    }

    public func pauseRecording() {
        guard state == .recording else { return }
        recordingService.pauseRecording()
        state = .paused
    }

    public func resumeRecording() {
        guard state == .paused else { return }
        recordingService.resumeRecording()
        state = .recording
    }

    public func startRecording() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "SuperHearing_\(timestamp).caf"

        state = .recording
        currentDuration = 0.0
        liveWaveform = [Float](repeating: 0.05, count: 40)

        Task {
            do {
                try await recordingService.startRecording(to: fileName)
                startMonitoring()
            } catch {
                self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                self.showError = true
                self.state = .idle
            }
        }
    }

    public func stopRecording() {
        stopMonitoring()
        state = .processing

        Task {
            do {
                let result = try await recordingService.stopRecording()
                let fileName = (recordingService as? RecordingService)?.value(forKey: "targetURL") as? URL

                let title = "Rec \(Date().formatted(date: .abbreviated, time: .shortened))"
                let resolvedFileName = fileName?.lastPathComponent ?? "Recording.caf"

                var audioFile = AudioFile(
                    title: title,
                    createdAt: Date(),
                    duration: result.duration,
                    fileName: resolvedFileName,
                    fileSize: result.fileSize,
                    waveformSamples: result.waveform
                )

                // Save to metadata library
                FileListViewModel.shared.add(audioFile)

                self.state = .ready(audioFile)
            } catch {
                self.errorMessage = "Failed to stop recording: \(error.localizedDescription)"
                self.showError = true
                self.state = .idle
            }
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentDuration = self.recordingService.currentDuration
                self.currentAmplitude = self.recordingService.currentAmplitude
                self.currentDBFS = self.recordingService.currentDBFS
                self.bluetoothDeviceName = self.recordingService.connectedBluetoothDevice

                // Push new sample to rolling waveform
                var wave = self.liveWaveform
                wave.removeFirst()
                wave.append(max(0.05, self.currentAmplitude))
                self.liveWaveform = wave
            }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
