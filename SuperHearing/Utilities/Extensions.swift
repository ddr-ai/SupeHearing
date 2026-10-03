import Foundation
import SwiftUI
import AVFoundation

public extension TimeInterval {
    /// Formats seconds to "MM:SS" or "MM:SS.s"
    func formattedPlaybackTime(includeFraction: Bool = false) -> String {
        let totalSeconds = max(0, self)
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        if includeFraction {
            let tenths = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 10)
            return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

public extension Float {
    /// Formats dBFS value cleanly with one decimal place.
    var formattedDB: String {
        if self <= -99.0 {
            return "-∞ dB"
        }
        return String(format: "%.1f dB", self)
    }

    /// Normalized value clamp.
    func clamped(to range: ClosedRange<Float> = 0.0...1.0) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public extension Double {
    func clamped(to range: ClosedRange<Double> = 0.0...1.0) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public extension URL {
    /// Returns the file size in bytes if file exists.
    var fileSize: Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Safely deletes the file if it exists.
    func removeIfExisting() {
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(at: self)
        }
    }
}

public extension View {
    /// Standard glass card styling for SuperHearing UI.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
    }
}
