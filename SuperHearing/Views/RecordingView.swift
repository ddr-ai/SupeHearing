import SwiftUI

public struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showingSettings = false
    @State private var showingProcessedSheet = false
    @State private var newlyRecordedFile: AudioFile?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Bluetooth Status Badge
                    bluetoothHeader

                    Spacer()

                    // Real-Time Waveform Display
                    liveWaveformSection

                    // Timer & Input Level Meter
                    meterAndTimerSection

                    Spacer()

                    // Quick Mode Toggles
                    quickTogglesSection

                    // Record / Pause / Stop Controls
                    controlButtonsSection

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("SuperHearing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $newlyRecordedFile, onDismiss: {
                if case .ready = viewModel.state {
                    viewModel.state = .idle
                }
            }) { file in
                ProcessingView(audioFile: file)
            }
            .onChange(of: viewModel.state) { _, newState in
                if case .ready(let file) = newState {
                    newlyRecordedFile = file
                }
            }
            .alert("SuperHearing", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unexpected error occurred.")
            }
        }
    }

    // MARK: - Bluetooth Header

    private var bluetoothHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.bluetoothDeviceName != nil ? "headphones" : "mic.fill")
                .foregroundColor(viewModel.bluetoothDeviceName != nil ? .blue : .secondary)

            Text(viewModel.bluetoothDeviceName ?? "Built-in Microphone")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            if viewModel.bluetoothDeviceName != nil {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
    }

    // MARK: - Real-Time Waveform

    private var liveWaveformSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<viewModel.liveWaveform.count, id: \.self) { idx in
                    let amp = CGFloat(viewModel.liveWaveform[idx])
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: max(6, amp * 120))
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: amp)
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Timer & Level Meter

    private var meterAndTimerSection: some View {
        VStack(spacing: 12) {
            Text(viewModel.currentDuration.formattedPlaybackTime(includeFraction: true))
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            // dBFS Horizontal VU Meter
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let clampedDB = max(-60.0, min(0.0, viewModel.currentDBFS))
                    let fraction = CGFloat((clampedDB + 60.0) / 60.0)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .yellow, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * fraction), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("-60 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.currentDBFS.formattedDB)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Quick Toggles

    private var quickTogglesSection: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $viewModel.autoNoiseReduction) {
                Label("Auto Noise Reduction", systemImage: "waveform.badge.minus")
                    .font(.footnote)
            }
            .toggleStyle(.button)
            .tint(.blue)

            Toggle(isOn: $viewModel.autoEnhancement) {
                Label("Auto Enhance", systemImage: "sparkles")
                    .font(.footnote)
            }
            .toggleStyle(.button)
            .tint(.purple)
        }
    }

    // MARK: - Controls

    private var controlButtonsSection: some View {
        HStack(spacing: 36) {
            // Pause / Resume Button
            if viewModel.state == .recording || viewModel.state == .paused {
                Button {
                    if viewModel.state == .recording {
                        viewModel.pauseRecording()
                    } else {
                        viewModel.resumeRecording()
                    }
                } label: {
                    Image(systemName: viewModel.state == .paused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                        )
                }
            } else {
                Spacer().frame(width: 56, height: 56)
            }

            // Main Record / Stop Action Button
            Button {
                viewModel.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 84, height: 84)

                    if viewModel.state == .recording || viewModel.state == .paused {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 68, height: 68)
                            .shadow(color: .red.opacity(0.4), radius: 10, y: 4)
                    }
                }
            }

            // Secondary Spacer / Reset
            Spacer().frame(width: 56, height: 56)
        }
    }
}
