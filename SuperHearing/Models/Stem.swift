import SwiftUI

/// Audio stems produced by 4-source separation (e.g. HTDemucs).
public enum Stem: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case vocals = "vocals"
    case drums = "drums"
    case bass = "bass"
    case other = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vocals: return "Vocals"
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .other: return "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .vocals: return "mic.fill"
        case .drums: return "tuningfork"
        case .bass: return "guitars.fill"
        case .other: return "music.note"
        }
    }

    public var description: String {
        switch self {
        case .vocals: return "Isolated speech and vocal frequencies"
        case .drums: return "Percussion, transients, and beats"
        case .bass: return "Low-frequency basslines and sub-bass"
        case .other: return "Atmosphere, instruments, and ambient backdrop"
        }
    }

    public var color: Color {
        switch self {
        case .vocals: return Color(red: 1.0, green: 0.27, blue: 0.23) // Electric Coral
        case .drums: return Color(red: 1.0, green: 0.62, blue: 0.04)  // Amber Gold
        case .bass: return Color(red: 0.19, green: 0.82, blue: 0.35)  // Bright Emerald
        case .other: return Color(red: 0.04, green: 0.52, blue: 1.0)  // Deep Azure
        }
    }

    public var hexColor: String {
        switch self {
        case .vocals: return "#FF453A"
        case .drums: return "#FF9F0A"
        case .bass: return "#30D158"
        case .other: return "#0A84FF"
        }
    }
}
