import UIKit
import AVFoundation

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setPreferredSampleRate(48000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AppDelegate] AudioSession setup error: \(error.localizedDescription)")
        }
    }
}
