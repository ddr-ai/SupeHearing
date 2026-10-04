import Foundation
import AVFoundation
import Accelerate

public struct RecordingResult: Sendable {
    public let url: URL
    public let fileName: String
    public let duration: TimeInterval
    public let fileSize: Int64
    public let waveform: [Float]

    public init(url: URL, fileName: String, duration: TimeInterval, fileSize: Int64, waveform: [Float]) {
        self.url = url
        self.fileName = fileName
        self.duration = duration
        self.fileSize = fileSize
        self.waveform = waveform
    }
}

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
    func stopRecording() async throws -> RecordingResult
}

/// Manages audio input routing, Bluetooth device detection, and real-time audio recording via AVAudioEngine.
public final class RecordingService: NSObject, RecordingServiceProtocol, @unchecked Sendable {
    public static let shared = RecordingService()

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var targetURL: URL?
    private var targetFileName: String?
    private var isTapInstalled: Bool = false
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
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
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
        self.targetFileName = fileName

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)

        // Guard against invalid hardware format
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48000.0
        let channelCount = hardwareFormat.channelCount > 0 ? hardwareFormat.channelCount : 1

        let safeHardwareFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) ?? hardwareFormat

        // Standard 48kHz mono float PCM recording format
        let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 1,
            interleaved: false
        )!

        // Create converter if hardware format differs
        let formatConverter = AVAudioConverter(from: safeHardwareFormat, to: recordFormat)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]

        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        lock.lock()
        self.audioFile = audioFile
        self.recordedSamples.removeAll(keepingCapacity: true)
        lock.unlock()

        circularBuffer.clear()

        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        let bufferSize: AVAudioFrameCount = 2048
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: safeHardwareFormat) { [weak self] buffer, time in
            guard let self = self, self.isRecording, !self.isPaused, buffer.frameLength > 0 else { return }

            if let converter = formatConverter {
                let frameRatio = 48000.0 / sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio) + 512
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
        isTapInstalled = true

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        isRecording = true
        isPaused = false
        accumulatedDuration = 0.0
        recordingStartTime = Date()

        startTimer()
    }

    private func processRecordedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Write to disk and store samples under lock
        lock.lock()
        if let audioFile = self.audioFile {
            try? audioFile.write(from: buffer)
        }
        let pointer = UnsafeBufferPointer(start: channelData, count: frameCount)
        recordedSamples.append(contentsOf: pointer)
        lock.unlock()

        // Write to circular buffer for real-time monitoring
        circularBuffer.append(samples: channelData, count: frameCount)

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

    public func stopRecording() async throws -> RecordingResult {
        guard isRecording else {
            throw NSError(domain: "SuperHearing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active recording to stop"])
        }

        guard let url = targetURL else {
            throw NSError(domain: "SuperHearing", code: 2, userInfo: [NSLocalizedDescriptionKey: "No target recording URL found"])
        }

        let recordedFileName = targetFileName ?? url.lastPathComponent

        if let start = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(start)
            recordingStartTime = nil
        }

        let finalDuration = accumulatedDuration

        // 1. Immediately flag recording as inactive so tap callbacks stop writing
        isRecording = false
        isPaused = false
        stopTimer()

        // 2. Safely remove tap on bus 0 if installed
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        // 3. Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // 4. Safely close audio file and snapshot recorded samples under lock
        lock.lock()
        self.audioFile = nil
        let samples = self.recordedSamples
        self.recordedSamples = []
        lock.unlock()

        currentAmplitude = 0.0
        currentDBFS = -100.0

        let fileSize = url.fileSize

        // Downsample to 60 waveform bars for library display
        let waveform = CircularAudioBuffer.downsample(samples: samples, targetPoints: 60)

        self.targetURL = nil
        self.targetFileName = nil

        return RecordingResult(
            url: url,
            fileName: recordedFileName,
            duration: finalDuration,
            fileSize: fileSize,
            waveform: waveform
        )
    }

    private func stopRecordingCleanup() {
        isRecording = false
        isPaused = false
        stopTimer()

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        lock.lock()
        audioFile = nil
        recordedSamples.removeAll(keepingCapacity: false)
        lock.unlock()

        targetURL = nil
        targetFileName = nil
        currentDuration = 0.0
        currentAmplitude = 0.0
        currentDBFS = -100.0
        accumulatedDuration = 0.0
        recordingStartTime = nil
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
