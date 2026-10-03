import Foundation
import AVFoundation
import Accelerate

public protocol RecordingServiceProtocol: AnyObject, Sendable {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var currentDuration: TimeInterval { get }
    var currentAmplitude: Float { get }
    var currentDBFS: Float { get }
    var connectedBluetoothDevice: String? { get }

    func startRecording(to fileName: String) async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording() async throws -> (duration: TimeInterval, fileSize: Int64, waveform: [Float])
}

/// Manages audio input routing, Bluetooth device detection, and real-time audio recording via AVAudioEngine.
public final class RecordingService: NSObject, RecordingServiceProtocol, @unchecked Sendable {
    public static let shared = RecordingService()

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var targetURL: URL?
    private let circularBuffer = CircularAudioBuffer(capacity: 48000 * 2)

    private var recordedSamples: [Float] = []
    private let lock = NSLock()

    public private(set) var isRecording: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var currentDuration: TimeInterval = 0.0
    public private(set) var currentAmplitude: Float = 0.0
    public private(set) var currentDBFS: Float = -100.0
    public private(set) var connectedBluetoothDevice: String?

    private var timer: Timer?
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0.0

    public override init() {
        super.init()
        setupAudioSession()
        setupNotifications()
        updateConnectedBluetoothDevice()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    // MARK: - Audio Session & Bluetooth Setup

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setPreferredSampleRate(48000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            routeToBluetoothIfAvailable()
        } catch {
            print("[RecordingService] AudioSession setup error: \(error.localizedDescription)")
        }
    }

    private func routeToBluetoothIfAvailable() {
        let session = AVAudioSession.sharedInstance()
        guard let inputs = session.availableInputs else { return }

        // Find Bluetooth HFP / A2DP input
        if let bluetoothInput = inputs.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
        }) {
            do {
                try session.setPreferredInput(bluetoothInput)
                connectedBluetoothDevice = bluetoothInput.portName
            } catch {
                print("[RecordingService] Failed to set preferred Bluetooth input: \(error)")
            }
        } else {
            connectedBluetoothDevice = nil
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        Task { @MainActor in
            self.updateConnectedBluetoothDevice()
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .began {
            pauseRecording()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resumeRecording()
                }
            }
        }
    }

    private func updateConnectedBluetoothDevice() {
        let session = AVAudioSession.sharedInstance()
        for input in session.currentRoute.inputs {
            if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP || input.portType == .bluetoothLE {
                connectedBluetoothDevice = input.portName
                return
            }
        }
        connectedBluetoothDevice = nil
    }

    // MARK: - Recording Actions

    public func startRecording(to fileName: String) async throws {
        stopRecordingCleanup()

        setupAudioSession()
        routeToBluetoothIfAvailable()

        let fileURL = AudioFile.recordingsDirectory.appendingPathComponent(fileName)
        fileURL.removeIfExisting()
        self.targetURL = fileURL

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)

        // Standard 48kHz mono float PCM recording format
        let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 1,
            interleaved: false
        )!

        // Create converter if hardware format differs
        let formatConverter = AVAudioConverter(from: hardwareFormat, to: recordFormat)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        let audioFile = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.audioFile = audioFile

        lock.lock()
        recordedSamples.removeAll(keepingCapacity: true)
        lock.unlock()
        circularBuffer.clear()

        inputNode.removeTap(onBus: 0)
        let bufferSize: AVAudioFrameCount = 2048

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self, self.isRecording, !self.isPaused else { return }

            if let converter = formatConverter {
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 48000.0 / hardwareFormat.sampleRate) + 512
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordFormat, frameCapacity: capacity) else { return }

                var error: NSError?
                var allConsumed = false
                converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    if !allConsumed {
                        allConsumed = true
                        outStatus.pointee = .haveData
                        return buffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }

                if error == nil && convertedBuffer.frameLength > 0 {
                    self.processRecordedBuffer(convertedBuffer)
                }
            } else {
                self.processRecordedBuffer(buffer)
            }
        }

        try audioEngine.start()

        isRecording = true
        isPaused = false
        accumulatedDuration = 0.0
        recordingStartTime = Date()

        startTimer()
    }

    private func processRecordedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Write to disk
        if let audioFile = self.audioFile {
            try? audioFile.write(from: buffer)
        }

        // Write to circular buffer for real-time monitoring
        circularBuffer.append(samples: channelData, count: frameCount)

        // Collect samples for waveform thumbnail
        lock.lock()
        let pointer = UnsafeBufferPointer(start: channelData, count: frameCount)
        recordedSamples.append(contentsOf: pointer)
        lock.unlock()

        // Update amplitude & dBFS
        let rms = circularBuffer.currentRMS(windowSize: 1024)
        let dbfs = CircularAudioBuffer.toDbFS(rms: rms)

        self.currentAmplitude = min(1.0, rms * 5.0)
        self.currentDBFS = dbfs
    }

    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        if let start = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(start)
            recordingStartTime = nil
        }
    }

    public func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        recordingStartTime = Date()
    }

    public func stopRecording() async throws -> (duration: TimeInterval, fileSize: Int64, waveform: [Float]) {
        guard isRecording else {
            throw NSError(domain: "SuperHearing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active recording to stop"])
        }

        if let start = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(start)
        }

        let finalDuration = accumulatedDuration

        stopTimer()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        self.audioFile = nil
        isRecording = false
        isPaused = false
        currentAmplitude = 0.0
        currentDBFS = -100.0

        let url = targetURL
        let fileSize = url?.fileSize ?? 0

        lock.lock()
        let samples = self.recordedSamples
        self.recordedSamples = []
        lock.unlock()

        // Downsample to 60 waveform bars for library display
        let waveform = CircularAudioBuffer.downsample(samples: samples, targetPoints: 60)

        return (duration: finalDuration, fileSize: fileSize, waveform: waveform)
    }

    private func stopRecordingCleanup() {
        stopTimer()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioFile = nil
        isRecording = false
        isPaused = false
        currentDuration = 0.0
    }

    private func startTimer() {
        stopTimer()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                if !self.isPaused, let start = self.recordingStartTime {
                    self.currentDuration = self.accumulatedDuration + Date().timeIntervalSince(start)
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
