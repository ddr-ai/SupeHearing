import SwiftUI

public struct MainTabView: View {
    public init() {}

    public var body: some View {
        TabView {
            RecordingView()
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }

            FileListView()
                .tabItem {
                    Label("Recordings", systemImage: "waveform")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
