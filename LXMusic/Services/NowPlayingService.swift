import Foundation
import MediaPlayer
import UIKit

enum RemoteCommand {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(Double)
}

/// 锁屏 / 控制中心 / 耳机线控
final class NowPlayingService {
    static let shared = NowPlayingService()
    private var didSetup = false

    func setup(handler: @escaping (RemoteCommand) -> Void) {
        guard !didSetup else { return }
        didSetup = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        center.playCommand.addTarget { _ in handler(.play); return .success }
        center.pauseCommand.addTarget { _ in handler(.pause); return .success }
        center.togglePlayPauseCommand.addTarget { _ in handler(.toggle); return .success }
        center.nextTrackCommand.addTarget { _ in handler(.next); return .success }
        center.previousTrackCommand.addTarget { _ in handler(.previous); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            if let position = event as? MPChangePlaybackPositionCommandEvent {
                handler(.seek(position.positionTime))
            }
            return .success
        }
    }

    func update(music: MusicInfo?,
                isPlaying: Bool,
                progress: Double,
                duration: Double,
                artwork: UIImage?) {
        guard let music = music else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: music.displayName,
            MPMediaItemPropertyArtist: music.displaySinger,
            MPMediaItemPropertyAlbumTitle: music.meta.albumName,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(progress, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
