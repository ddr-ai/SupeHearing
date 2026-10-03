import SwiftUI

public struct SeparationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SeparationViewModel
    @State private var showingMixer = false

    public init(audioFile: AudioFile) {
        _viewModel = StateObject(wrappedValue: SeparationViewModel(audioFile: audioFile))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Status Card
                    statusCard

                    // Separation Progress Card
                    if viewModel.isSeparating {
                        progressCard
                    }

                    // Separated Stems Cards
                    if !viewModel.stems.isEmpty {
                        stemsOverviewSection

                        Button {
                            showingMixer = true
                        } label: {
                            Label("Open 4-Track Stem Mixer", systemImage: "slider.vertical.3")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("4-Source Separation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingMixer) {
                StemMixerView(stemURLs: viewModel.stems)
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(viewModel.modelName, systemImage: "cpu")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)

                Spacer()

                if viewModel.isModelAvailable {
                    Text("CoreML ANE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }

            Text("Separates recorded audio into 4 distinct stems: Vocals (speech), Drums (transients), Bass, and Ambient background.")
                .font(.footnote)
                .foregroundColor(.secondary)

            if !viewModel.isSeparating && viewModel.stems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Separation Quality:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Quality", selection: $viewModel.quality) {
                        ForEach(SeparationQuality.allCases, id: \.self) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    viewModel.startSeparation()
                } label: {
                    Text("Start Stem Separation")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.progress)
                .tint(.purple)

            HStack {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.footnote)
                    .fontWeight(.semibold)
            }

            Button(role: .cancel) {
                viewModel.cancelSeparation()
            } label: {
                Text("Cancel")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Stems Overview Section

    private var stemsOverviewSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Extracted Stems")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            ForEach(Stem.allCases) { stem in
                if let url = viewModel.stems[stem] {
                    StemCardRow(
                        stem: stem,
                        fileURL: url,
                        isPlaying: viewModel.playingStem == stem,
                        onPlayToggle: {
                            viewModel.previewStem(stem)
                        }
                    )
                }
            }
        }
    }
}

public struct StemCardRow: View {
    public let stem: Stem
    public let fileURL: URL
    public let isPlaying: Bool
    public let onPlayToggle: () -> Void

    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(stem.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: stem.systemImage)
                    .foregroundColor(stem.color)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stem.displayName)
                    .font(.headline)
                Text(stem.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onPlayToggle) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(stem.color)
            }

            ShareLink(item: fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.secondary)
            }
        }
        .glassCard()
        .padding(.horizontal)
    }
}
