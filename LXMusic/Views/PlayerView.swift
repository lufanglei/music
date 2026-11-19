import SwiftUI

struct PlayerView: View {
    @ObservedObject private var player = PlayerService.shared
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var sliderValue: Double = 0
    @State private var isEditing = false
    @State private var showLyrics = false

    var body: some View {
        GeometryReader { geo in
            content(artSize: min(geo.size.width - 88, geo.size.height * 0.34))
        }
        .sheet(isPresented: $showQueue) {
            QueueView().environmentObject(LibraryStore.shared)
        }
    }

    private func content(artSize: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.10, green: 0.13, blue: 0.24),
                Color(red: 0.22, green: 0.17, blue: 0.36),
                Color(red: 0.07, green: 0.09, blue: 0.17),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 6)
                if showLyrics {
                    lyricsPanel
                } else {
                    artworkPanel(artSize: artSize)
                }
                Spacer(minLength: 6)
                titlePanel
                sliderPanel
                controlsPanel
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.borderless)
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放").font(.caption).foregroundColor(.white.opacity(0.7))
                Text("LX Music").font(.caption2).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.borderless)
        }
    }

    private func artworkPanel(artSize: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
        } label: {
            ArtworkView(urlString: player.current?.meta.picUrl, size: artSize, cornerRadius: 22)
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
        }
        .buttonStyle(.plain)
    }

    private var lyricsPanel: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if player.lyrics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.35))
                        Text("暂无歌词 · 点击封面返回")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 14) {
                                ForEach(player.lyrics) { line in
                                    Text(line.text)
                                        .font(.system(size: line.id == player.currentLyricIndex ? 18 : 15,
                                                      weight: line.id == player.currentLyricIndex ? .semibold : .regular))
                                        .foregroundColor(.white.opacity(line.id == player.currentLyricIndex ? 1 : 0.45))
                                        .multilineTextAlignment(.center)
                                        .id(line.id)
                                        .padding(.horizontal, 12)
                                }
                            }
                            .padding(.vertical, 80)
                        }
                        .onChange(of: player.currentLyricIndex) { index in
                            if let index = index {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 230)
        }
        .buttonStyle(.plain)
    }

    private var titlePanel: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(player.current?.displayName ?? "未在播放")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(player.current?.displaySinger ?? "")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                if let error = player.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let music = player.current {
                Button { library.toggleFavorite(music) } label: {
                    Image(systemName: library.isFavorite(music) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundColor(library.isFavorite(music) ? .pink : .white.opacity(0.7))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 18)
    }

    private var sliderPanel: some View {
        VStack(spacing: 4) {
            Slider(value: $sliderValue,
                   in: 0...max(player.duration, 1),
                   onEditingChanged: { editing in
                       isEditing = editing
                       if !editing { player.seek(to: sliderValue) }
                   },
                   label: { EmptyView() })
                .tint(.white)
            HStack {
                Text(timeText(player.progress))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(timeText(player.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.top, 12)
        .onChange(of: player.progress) { value in
            if !isEditing { sliderValue = value }
        }
        .onChange(of: player.duration) { _ in sliderValue = 0 }
    }

    private var controlsPanel: some View {
        HStack(spacing: 0) {
            Button { player.setMode(nextMode) } label: {
                Image(systemName: player.mode.symbol)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.borderless)
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title2).foregroundColor(.white)
            }
            .buttonStyle(.borderless)
            Spacer()
            Button { player.toggle() } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 66, height: 66)
                    if player.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.black)
                    }
                }
            }
            .buttonStyle(.borderless)
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title2).foregroundColor(.white)
            }
            .buttonStyle(.borderless)
            Spacer()
            Button { showLyrics.toggle() } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.borderless)
        }
        .padding(.top, 14)
    }

    private var nextMode: PlayMode {
        let all = PlayMode.allCases
        let index = all.firstIndex(of: player.mode) ?? 0
        return all[(index + 1) % all.count]
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct QueueItem: Identifiable {
    let index: Int
    let music: MusicInfo
    var id: String { "\(index)_\(music.id)" }
}

struct QueueView: View {
    @ObservedObject private var player = PlayerService.shared
    @Environment(\.dismiss) private var dismiss

    private var items: [QueueItem] {
        player.queue.enumerated().map { QueueItem(index: $0.offset, music: $0.element) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button {
                        player.playAt(item.index)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(urlString: item.music.meta.picUrl, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.music.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(item.index == player.currentIndex ? .accentColor : .primary)
                                    .lineLimit(1)
                                Text(item.music.displaySinger)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if item.index == player.currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in player.removeFromQueue(at: offsets) }

                if !player.queue.isEmpty {
                    Button("清空队列", role: .destructive) { player.clearQueue() }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("播放队列 · \(player.queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
