import Foundation

/// Holds details of a separated multi-stem audio session.
public struct SeparatedAudio: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let originalAudioId: UUID
    public let createdAt: Date
    public let duration: TimeInterval
    public var stemFileNames: [Stem: String]
    public var modelName: String

    public init(
        id: UUID = UUID(),
        originalAudioId: UUID,
        createdAt: Date = Date(),
        duration: TimeInterval,
        stemFileNames: [Stem: String],
        modelName: String = "HTDemucs-v4-INT8"
    ) {
        self.id = id
        self.originalAudioId = originalAudioId
        self.createdAt = createdAt
        self.duration = duration
        self.stemFileNames = stemFileNames
        self.modelName = modelName
    }

    public func fileURL(for stem: Stem) -> URL? {
        guard let name = stemFileNames[stem] else { return nil }
        return AudioFile.recordingsDirectory.appendingPathComponent(name)
    }
}
