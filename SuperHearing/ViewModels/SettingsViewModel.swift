import Foundation
import SwiftUI
import Combine

@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("nrStrength") public var nrStrength: Double = 1.5
    @AppStorage("enhancementLevel") public var enhancementLevel: Double = 1.0
    @AppStorage("sampleRateChoice") public var sampleRateChoice: String = "48000"
    @AppStorage("separationQuality") public var separationQualityRaw: String = SeparationQuality.balanced.rawValue
    @AppStorage("autoSeparate") public var autoSeparate: Bool = false
    @AppStorage("autoConnectBluetooth") public var autoConnectBluetooth: Bool = true

    @Published public var cacheSizeBytes: Int64 = 0
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false

    public init() {
        calculateStorage()
    }

    public var separationQuality: SeparationQuality {
        get { SeparationQuality(rawValue: separationQualityRaw) ?? .balanced }
        set { separationQualityRaw = newValue.rawValue }
    }

    public var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    public func calculateStorage() {
        let dir = AudioFile.recordingsDirectory
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(size)
                }
            }
        }
        self.cacheSizeBytes = total
    }

    public func clearAllRecordings() {
        let dir = AudioFile.recordingsDirectory
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let metaURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("recordings_meta.json")
        try? FileManager.default.removeItem(at: metaURL)

        FileListViewModel.shared.loadFiles()
        calculateStorage()

        alertMessage = "All recordings and cached files have been cleared."
        showAlert = true
    }

    public func resetToDefaults() {
        nrStrength = 1.5
        enhancementLevel = 1.0
        sampleRateChoice = "48000"
        separationQuality = .balanced
        autoSeparate = false
        autoConnectBluetooth = true

        alertMessage = "Audio settings restored to defaults."
        showAlert = true
    }
}
