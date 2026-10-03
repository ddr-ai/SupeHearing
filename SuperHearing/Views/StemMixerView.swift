import SwiftUI

public struct StemMixerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StemMixerViewModel

    public init(stemURLs: [Stem: URL]) {
        _viewModel = StateObject(wrappedValue: StemMixerViewModel(stemURLs: stemURLs))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 4-Channel Strips Rack
                HStack(spacing: 8) {
                    ForEach(Stem.allCases) { stem in
                        StemChannelStrip(
                            stem: stem,
                            gain: Binding(
                                get: { viewModel.gains[stem] ?? 1.0 },
                                set: { viewModel.setGain(stem: stem, gain: $0) }
                            ),
                            pan: Binding(
                                get: { viewModel.pans[stem] ?? 0.0 },
                                set: { viewModel.setPan(stem: stem, pan: $0) }
                            ),
                            isSoloed: viewModel.soloedStems.contains(stem),
                            isMuted: viewModel.mutedStems.contains(stem),
                            onToggleSolo: { viewModel.toggleSolo(stem: stem) },
                            onToggleMute: { viewModel.toggleMute(stem: stem) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)

                Divider()

                // Master Transport & Export Section
                transportAndMasterSection
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("4-Track Stem Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.exportMix()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Export Mix")
                        }
                    }
                    .disabled(viewModel.isExporting)
                }
            }
            .alert("Mix Export", isPresented: Binding(
                get: { viewModel.exportMessage != nil },
                set: { if !$0 { viewModel.exportMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.exportMessage ?? "")
            }
        }
    }

    // MARK: - Master Section

    private var transportAndMasterSection: some View {
        VStack(spacing: 12) {
            // Seek bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { viewModel.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(0.1, viewModel.duration)
                )

                HStack {
                    Text(viewModel.currentTime.formattedPlaybackTime(includeFraction: true))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(viewModel.duration.formattedPlaybackTime(includeFraction: true))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            // Playback buttons & Master Fader
            HStack(spacing: 24) {
                // Loop Button
                Button {
                    viewModel.toggleLoop()
                } label: {
                    Image(systemName: "repeat")
                        .foregroundColor(viewModel.loopEnabled ? .accentColor : .secondary)
                        .font(.title3)
                }

                // Play / Pause Button
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.accentColor)
                }

                // Master Volume Slider
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)

                    Slider(
                        value: Binding(
                            get: { viewModel.masterVolume },
                            set: { viewModel.setMasterVolume($0) }
                        ),
                        in: 0...1.5
                    )
                    .frame(maxWidth: 120)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal)
    }
}

public struct StemChannelStrip: View {
    public let stem: Stem
    @Binding public var gain: Float
    @Binding public var pan: Float
    public let isSoloed: Bool
    public let isMuted: Bool
    public let onToggleSolo: () -> Void
    public let onToggleMute: () -> Void

    public var body: some View {
        VStack(spacing: 10) {
            // Track Header
            VStack(spacing: 4) {
                Image(systemName: stem.systemImage)
                    .font(.subheadline)
                    .foregroundColor(stem.color)
                Text(stem.displayName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
            .frame(height: 38)

            // Solo & Mute Buttons
            HStack(spacing: 4) {
                Button(action: onToggleSolo) {
                    Text("S")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .frame(width: 24, height: 24)
                        .background(isSoloed ? Color.yellow : Color(.tertiarySystemFill))
                        .foregroundColor(isSoloed ? .black : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button(action: onToggleMute) {
                    Text("M")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .frame(width: 24, height: 24)
                        .background(isMuted ? Color.red : Color(.tertiarySystemFill))
                        .foregroundColor(isMuted ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Pan Slider
            VStack(spacing: 2) {
                Text(panString(pan))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                Slider(value: $pan, in: -1.0...1.0)
                    .scaleEffect(x: 0.8, y: 0.8)
                    .frame(height: 16)
            }

            // Vertical Fader
            VStack(spacing: 4) {
                Text(gainDBString(gain))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(stem.color)

                Slider(value: $gain, in: 0.0...1.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 40)
                    .padding(.vertical, 50)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSoloed ? Color.yellow.opacity(0.8) : Color.clear, lineWidth: 2)
                )
        )
    }

    private func gainDBString(_ val: Float) -> String {
        if val <= 0.001 { return "-∞" }
        let db = 20.0 * log10(val)
        return String(format: "%+.0fdB", db)
    }

    private func panString(_ p: Float) -> String {
        if abs(p) < 0.05 { return "C" }
        if p < 0 { return String(format: "L%02.0f", abs(p) * 100) }
        return String(format: "R%02.0f", p * 100)
    }
}
