import Foundation
import AVFoundation
import UIKit

/// AVPlayer 播放核心：播放队列、播放模式、进度、歌词、封面、后台与锁屏控制
final class PlayerService: ObservableObject {
    static let shared = PlayerService()

    @Published var current: MusicInfo?
    @Published var queue: [MusicInfo] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var mode: PlayMode = .listLoop
    @Published var lyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int?
    @Published var errorMessage: String?
    @Published var artwork: UIImage?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var generation = 0

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "lx.player.mode"),
           let saved = PlayMode(rawValue: raw) {
            mode = saved
        }
        NowPlayingService.shared.setup { [weak self] command in
            guard let self = self else { return }
            switch command {
            case .play: self.resume()
            case .pause: self.pause()
            case .toggle: self.toggle()
            case .next: self.next()
            case .previous: self.previous()
            case .seek(let time): self.seek(to: time)
            }
        }
        setupNotifications()
    }

    deinit {
        clearPlayerObservers()
        [interruptionObserver, routeObserver].compactMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    // MARK: - 播放入口

    func play(_ music: MusicInfo, in list: [MusicInfo] = []) {
        if !list.isEmpty { queue = list }
        if !queue.contains(where: { $0.id == music.id }) { queue.append(music) }
        if let index = queue.firstIndex(where: { $0.id == music.id }) { currentIndex = index }
        startCurrent()
    }

    func playAll(_ list: [MusicInfo]) {
        guard let first = list.first else { return }
        play(first, in: list)
    }

    func playAt(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        startCurrent()
    }

    func appendToQueue(_ music: MusicInfo) {
        queue.append(music)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard let removed = offsets.first, removed < queue.count else { return }
        let wasCurrent = removed == currentIndex
        queue.remove(atOffsets: offsets)
        if queue.isEmpty {
            stop()
            return
        }
        if removed < currentIndex { currentIndex -= 1 }
        currentIndex = min(currentIndex, queue.count - 1)
        if wasCurrent { startCurrent() }
    }

    func clearQueue() {
        queue.removeAll()
        stop()
    }

    private func stop() {
        clearPlayerObservers()
        player?.pause()
        player = nil
        current = nil
        isPlaying = false
        progress = 0
        duration = 0
        lyrics = []
        artwork = nil
        NowPlayingService.shared.update(music: nil, isPlaying: false, progress: 0, duration: 0, artwork: nil)
    }

    // MARK: - 控制

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard player != nil else {
            if current != nil { startCurrent() }
            return
        }
        AudioSessionManager.shared.activate()
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if mode == .shuffle, queue.count > 1 {
            var index = currentIndex
            while index == currentIndex { index = Int.random(in: 0..<queue.count) }
            currentIndex = index
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }
        startCurrent()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if progress > 3 {
            seek(to: 0)
            return
        }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        startCurrent()
    }

    func seek(to seconds: Double) {
        let value = max(0, seconds)
        let time = CMTime(seconds: value, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.updateNowPlaying()
        }
        progress = value
        currentLyricIndex = LyricParser.currentIndex(lines: lyrics, time: value)
    }

    func setMode(_ newMode: PlayMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "lx.player.mode")
    }

    // MARK: - 内部：加载并播放

    private func startCurrent() {
        guard currentIndex >= 0, currentIndex < queue.count else { return }
        generation += 1
        let token = generation
        let music = queue[currentIndex]

        clearPlayerObservers()
        player?.pause()

        current = music
        progress = 0
        duration = 0
        lyrics = []
        currentLyricIndex = nil
        errorMessage = nil
        artwork = nil
        isLoading = true
        isPlaying = false

        AudioSessionManager.shared.activate()
        NowPlayingService.shared.update(music: music, isPlaying: false, progress: 0, duration: 0, artwork: nil)
        fetchArtwork(for: music, token: token)
        fetchLyrics(for: music, token: token)

        SourceManager.shared.musicURL(for: music) { [weak self] result in
            guard let self = self, self.generation == token else { return }
            self.isLoading = false
            switch result {
            case .success(let url):
                SettingsStore.shared.log("开始播放: \(music.name)")
                self.replacePlayer(with: url)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                SettingsStore.shared.log("播放失败: \(error.localizedDescription)")
            }
        }
    }

    private func replacePlayer(with url: URL) {
        clearPlayerObservers()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTimeMake(value: 1, timescale: 2),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds >= 0 else { return }
            self.progress = seconds
            if let total = self.player?.currentItem?.duration {
                let value = CMTimeGetSeconds(total)
                if value.isFinite, value > 0 { self.duration = value }
            }
            self.currentLyricIndex = LyricParser.currentIndex(lines: self.lyrics, time: seconds)
            self.updateNowPlaying()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.mode == .singleLoop {
                self.seek(to: 0)
                self.resume()
            } else {
                self.next()
            }
        }

        newPlayer.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func clearPlayerObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }

    private func updateNowPlaying() {
        NowPlayingService.shared.update(music: current,
                                        isPlaying: isPlaying,
                                        progress: progress,
                                        duration: duration,
                                        artwork: artwork)
    }

    private func fetchArtwork(for music: MusicInfo, token: Int) {
        guard let pic = music.meta.picUrl, !pic.isEmpty else { return }
        if FileManager.default.fileExists(atPath: pic) {
            if let image = UIImage(contentsOfFile: pic) {
                artwork = image
                updateNowPlaying()
            }
            return
        }
        guard let url = URL(string: pic),
              url.scheme == "http" || url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.generation == token else { return }
                self?.artwork = image
                self?.updateNowPlaying()
            }
        }.resume()
    }

    private func fetchLyrics(for music: MusicInfo, token: Int) {
        SourceManager.shared.lyric(for: music) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                guard case .success(let lyric) = result else { return }
                let hasWordByWord = !(lyric.lxlyric?.isEmpty ?? true)
                let text = hasWordByWord ? (lyric.lxlyric ?? "") : lyric.lyric
                self.lyrics = LyricParser.parse(text)
            }
        }
    }

    // MARK: - 中断 / 路由变化

    private func setupNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.pause()
            } else if type == .ended {
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                    self.resume()
                }
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable else { return }
            self?.pause()
        }
    }
}
