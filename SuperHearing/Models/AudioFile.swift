import Foundation
import SwiftUI

/// Audio file format type.
public enum AudioFileFormat: String, Codable, Sendable {
    case caf = "caf"
    case m4a = "m4a"
    case wav = "wav"

    public var displayName: String {
        switch self {
        case .caf: return "CAF (PCM)"
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV"
        }
    }
}

/// Processing status of the recorded audio.
public enum ProcessingStatus: String, Codable, Sendable {
    case raw = "raw"
    case processing = "processing"
    case processed = "processed"
    case separated = "separated"

    public var badgeTitle: String {
        switch self {
        case .raw: return "Raw"
        case .processing: return "Processing"
        case .processed: return "Processed"
        case .separated: return "Separated"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .raw: return .gray
        case .processing: return .orange
        case .processed: return .green
        case .separated: return .purple
        }
    }
}

/// Represents an audio recording in SuperHearing.
public struct AudioFile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var duration: TimeInterval
    public var fileName: String
    public var fileSize: Int64
    public var sampleRate: Double
    public var format: AudioFileFormat
    public var status: ProcessingStatus
    public var processedFileName: String?
    public var stemFileNames: [Stem: String]?
    public var waveformSamples: [Float]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        fileName: String,
        fileSize: Int64,
        sampleRate: Double = 48000.0,
        format: AudioFileFormat = .caf,
        status: ProcessingStatus = .raw,
        processedFileName: String? = nil,
        stemFileNames: [Stem: String]? = nil,
        waveformSamples: [Float] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.sampleRate = sampleRate
        self.format = format
        self.status = status
        self.processedFileName = processedFileName
        self.stemFileNames = stemFileNames
        self.waveformSamples = waveformSamples
    }

    /// Resolves the URL for the raw file inside the app documents recordings directory.
    public var fileURL: URL {
        Self.recordingsDirectory.appendingPathComponent(fileName)
    }

    /// Resolves the processed file URL if available.
    public var processedURL: URL? {
        guard let processedFileName else { return nil }
        return Self.recordingsDirectory.appendingPathComponent(processedFileName)
    }

    /// Resolves individual stem URLs if available.
    public var stemURLs: [Stem: URL]? {
        guard let stemFileNames else { return nil }
        var result: [Stem: URL] = [:]
        for (stem, name) in stemFileNames {
            result[stem] = Self.recordingsDirectory.appendingPathComponent(name)
        }
        return result
    }

    /// App recordings directory in Documents.
    public static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
