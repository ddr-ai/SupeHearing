import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Audio Processing
                Section(header: Text("Audio Engine")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Noise Reduction Strength")
                            Spacer()
                            Text(String(format: "%.1fx", viewModel.nrStrength))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.nrStrength, in: 0.5...3.0, step: 0.1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Distant Sound Boost")
                            Spacer()
                            Text(String(format: "%.1fx", viewModel.enhancementLevel))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.enhancementLevel, in: 0.5...2.0, step: 0.1)
                    }

                    Picker("Recording Sample Rate", selection: $viewModel.sampleRateChoice) {
                        Text("48.0 kHz (Bluetooth Standard)").tag("48000")
                        Text("44.1 kHz (CD Audio)").tag("44100")
                    }
                }

                // Section 2: Source Separation
                Section(header: Text("HTDemucs Source Separation")) {
                    Picker("Separation Quality", selection: $viewModel.separationQualityRaw) {
                        ForEach(SeparationQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality.rawValue)
                        }
                    }

                    Toggle("Auto-Separate After Processing", isOn: $viewModel.autoSeparate)
                }

                // Section 3: Bluetooth & Routing
                Section(header: Text("Bluetooth Routing")) {
                    Toggle("Auto-Route to Bluetooth Headset", isOn: $viewModel.autoConnectBluetooth)

                    HStack {
                        Text("Target Profile")
                        Spacer()
                        Text("A2DP + HFP Wideband")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Section 4: Storage Management
                Section(header: Text("Storage")) {
                    HStack {
                        Text("Recordings & Stem Cache")
                        Spacer()
                        Text(viewModel.formattedCacheSize)
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        viewModel.clearAllRecordings()
                    } label: {
                        Text("Clear All Recordings & Cache")
                    }
                }

                // Section 5: About & Model Info
                Section(header: Text("About SuperHearing")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Neural Separation Model")
                        Spacer()
                        Text("HTDemucs v4 INT8")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Compute Units")
                        Spacer()
                        Text("Apple Neural Engine + GPU")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Accelerate Framework")
                        Spacer()
                        Text("vDSP Real FFT (1024-pt)")
                            .foregroundColor(.secondary)
                    }

                    Button {
                        viewModel.resetToDefaults()
                    } label: {
                        Text("Reset All Settings to Defaults")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("SuperHearing", isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
        }
    }
}
