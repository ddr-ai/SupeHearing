import SwiftUI

public struct FileListView: View {
    @ObservedObject private var viewModel = FileListViewModel.shared
    @State private var processingTargetFile: AudioFile?
    @State private var separationTargetFile: AudioFile?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Segmented Control
                Picker("Filter", selection: $viewModel.selectedFilter) {
                    ForEach(FileFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if viewModel.filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(viewModel.filteredFiles) { file in
                            AudioFileRow(
                                file: file,
                                isPlaying: viewModel.playingFileID == file.id && viewModel.isPlaying,
                                progress: viewModel.playingFileID == file.id ? viewModel.playbackProgress : 0.0,
                                onPlayToggle: {
                                    viewModel.togglePlayback(for: file)
                                },
                                onProcess: {
                                    processingTargetFile = file
                                },
                                onSeparate: {
                                    separationTargetFile = file
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.delete(file: file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    separationTargetFile = file
                                } label: {
                                    Label("Separate", systemImage: "tuningfork")
                                }
                                .tint(.purple)

                                Button {
                                    processingTargetFile = file
                                } label: {
                                    Label("Process", systemImage: "sparkles")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.togglePlayback(for: file)
                                } label: {
                                    Label(
                                        viewModel.playingFileID == file.id && viewModel.isPlaying ? "Pause" : "Play",
                                        systemImage: viewModel.playingFileID == file.id && viewModel.isPlaying ? "pause.fill" : "play.fill"
                                    )
                                }
                                .tint(.green)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        viewModel.loadFiles()
                    }
                }
            }
            .navigationTitle("Recordings")
            .sheet(item: $processingTargetFile) { file in
                ProcessingView(audioFile: file)
            }
            .sheet(item: $separationTargetFile) { file in
                SeparationView(audioFile: file)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 54))
                .foregroundColor(.secondary)

            Text("No Recordings Yet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Connect your Bluetooth headset and record ambient audio from the Record tab.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

public struct AudioFileRow: View {
    public let file: AudioFile
    public let isPlaying: Bool
    public let progress: Double
    public let onPlayToggle: () -> Void
    public let onProcess: () -> Void
    public let onSeparate: () -> Void

    public var body: some View {
        HStack(spacing: 14) {
            // Play / Pause Circle with Progress Ring
            Button(action: onPlayToggle) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        .frame(width: 44, height: 44)

                    if isPlaying {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                    }

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)

            // File Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    // Status Badge
                    Text(file.status.badgeTitle)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(file.status.badgeColor.opacity(0.15))
                        .foregroundColor(file.status.badgeColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Text(file.formattedDuration)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(file.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(file.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Mini Waveform Preview
                if !file.waveformSamples.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(30, file.waveformSamples.count), id: \.self) { idx in
                            let val = CGFloat(file.waveformSamples[idx])
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isPlaying ? Color.blue : Color.secondary.opacity(0.4))
                                .frame(width: 2, height: max(3, val * 20))
                        }
                    }
                    .frame(height: 22)
                }
            }

            // Action Menu
            Menu {
                Button(action: onProcess) {
                    Label("Noise Reduction & Enhance", systemImage: "sparkles")
                }
                Button(action: onSeparate) {
                    Label("4-Stem Separation", systemImage: "tuningfork")
                }
                ShareLink(item: file.processedURL ?? file.fileURL) {
                    Label("Share Audio File", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 4)
    }
}
