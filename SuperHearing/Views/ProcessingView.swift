import SwiftUI

public struct ProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProcessingViewModel
    @State private var showingSeparation = false

    public init(audioFile: AudioFile) {
        _viewModel = StateObject(wrappedValue: ProcessingViewModel(audioFile: audioFile))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Processing Status / Progress Ring
                    statusSection

                    // Adjustment Sliders (When not running)
                    if !viewModel.isProcessing && viewModel.stage != .completed {
                        parametersSection
                    }

                    // A/B Comparison Player (When completed or processed file available)
                    if viewModel.canCompare {
                        abComparisonSection
                    }

                    // Separation Next Step Action
                    if viewModel.stage == .completed || viewModel.canCompare {
                        Button {
                            showingSeparation = true
                        } label: {
                            Label("Separate into 4 Stems (HTDemucs)", systemImage: "tuningfork")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Noise Reduction & Enhance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        viewModel.cancelProcessing()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSeparation) {
                SeparationView(audioFile: viewModel.audioFile)
            }
        }
    }

    // MARK: - Status & Progress Ring

    private var statusSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0.0, to: CGFloat(viewModel.progress))
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.easeInOut, value: viewModel.progress)

                VStack(spacing: 2) {
                    if viewModel.isProcessing {
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                    } else if viewModel.stage == .completed {
                        Image(systemName: "checkmark")
                            .font(.title)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                }
            }

            Text(viewModel.stage.rawValue)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            if viewModel.isProcessing {
                Button(role: .cancel) {
                    viewModel.cancelProcessing()
                } label: {
                    Text("Cancel Processing")
                        .foregroundColor(.red)
                }
            } else if viewModel.stage != .completed {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Text("Start Processing")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Parameters

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Enhancement Parameters")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Noise Reduction Strength")
                    Spacer()
                    Text(String(format: "%.1f x", viewModel.nrStrength))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                Slider(value: $viewModel.nrStrength, in: 0.5...3.0, step: 0.1)
                Text("Higher values remove more stationary background hum, air conditioning, and fan noise.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Distant Sound Boost")
                    Spacer()
                    Text(String(format: "%.1f x", viewModel.enhancementIntensity))
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
                Slider(value: $viewModel.enhancementIntensity, in: 0.5...2.0, step: 0.1)
                Text("Amplifies low-energy distant speech formants (2-6 kHz) and applies AGC compression.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Toggle(isOn: $viewModel.useWienerFilter) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wiener Filter Mode")
                    Text("Minimizes musical chirping artifacts using statistical SNR estimation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - A/B Comparison Section

    private var abComparisonSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("A/B Audio Comparison")
                    .font(.headline)
                Spacer()
            }

            // Track Switcher: Original vs Processed
            Picker("Track", selection: Binding(
                get: { viewModel.activeABTrack },
                set: { viewModel.selectABTrack($0) }
            )) {
                Text("Original (Raw)").tag(ABComparisonTrack.original)
                Text("Processed (Enhanced)").tag(ABComparisonTrack.processed)
            }
            .pickerStyle(.segmented)

            // Playback Transport
            HStack(spacing: 20) {
                Button {
                    viewModel.toggleABPlayback()
                } label: {
                    Image(systemName: viewModel.isPlayingAB ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.activeABTrack == .processed ? "Enhanced Master Track" : "Original Raw Capture")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(viewModel.abCurrentTime.formattedPlaybackTime()) / \(viewModel.abDuration.formattedPlaybackTime())")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .glassCard()
        .padding(.horizontal)
    }
}
