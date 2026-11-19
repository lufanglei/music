import Foundation
import AVFoundation

/// 后台播放所需的音频会话。Info.plist 同时声明了 UIBackgroundModes = audio。
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private var didActivate = false

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            SettingsStore.shared.log("音频会话激活失败: \(error.localizedDescription)")
        }
    }
}
