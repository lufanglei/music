import SwiftUI
import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

final class ArtworkLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentKey: String?

    func load(_ key: String?) {
        currentKey = key
        image = nil
        guard let key = key, !key.isEmpty else { return }
        if let cached = ImageCache.shared.image(for: key) {
            image = cached
            return
        }
        if FileManager.default.fileExists(atPath: key) {
            if let local = UIImage(contentsOfFile: key) {
                ImageCache.shared.set(local, for: key)
                image = local
            }
            return
        }
        guard let url = URL(string: key),
              url.scheme == "http" || url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let remote = UIImage(data: data) else { return }
            ImageCache.shared.set(remote, for: key)
            DispatchQueue.main.async {
                guard self?.currentKey == key else { return }
                self?.image = remote
            }
        }.resume()
    }
}

struct ArtworkView: View {
    let urlString: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat?
    @StateObject private var loader = ArtworkLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [
                    Color(red: 0.26, green: 0.44, blue: 0.92),
                    Color(red: 0.58, green: 0.33, blue: 0.85),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.18, style: .continuous))
        .onAppear { loader.load(urlString) }
        .onChange(of: urlString) { _ in loader.load(urlString) }
    }
}

struct SongRow: View {
    @EnvironmentObject var library: LibraryStore
    let music: MusicInfo
    /// 排行榜、歌单详情里可显示序号
    var index: Int? = nil
    let onPlay: () -> Void

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if let index = index {
                    Text("\(index)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
                ArtworkView(urlString: music.meta.picUrl, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    HStack(spacing: 5) {
                        Text(music.displaySinger)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let interval = music.interval, !interval.isEmpty {
                            Text("·").font(.caption).foregroundColor(.secondary)
                            Text(interval).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(action: { library.toggleFavorite(music) }) {
                    Image(systemName: library.isFavorite(music) ? "heart.fill" : "heart")
                        .font(.system(size: 17))
                        .foregroundColor(library.isFavorite(music) ? .pink : .secondary.opacity(0.55))
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { library.toggleFavorite(music) } label: {
                Label(library.isFavorite(music) ? "取消喜欢" : "我喜欢", systemImage: "heart")
            }
            Button { PlayerService.shared.appendToQueue(music) } label: {
                Label("加入播放队列", systemImage: "text.badge.plus")
            }
            Menu {
                ForEach(library.playlists) { playlist in
                    Button { library.add(music, to: playlist.id) } label: {
                        Label(playlist.name, systemImage: "music.note.list")
                    }
                }
                Divider()
                Button {
                    newPlaylistName = ""
                    showNewPlaylist = true
                } label: {
                    Label("新建歌单…", systemImage: "plus")
                }
            } label: {
                Label("添加到歌单", systemImage: "text.badge.plus")
            }
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("取消", role: .cancel) { newPlaylistName = "" }
            Button("创建并添加") {
                library.createPlaylist(name: newPlaylistName)
                if let created = library.playlists.last {
                    library.add(music, to: created.id)
                }
                newPlaylistName = ""
            }
        } message: {
            Text("会创建新歌单并把「\(music.displayName)」加进去。")
        }
    }
}

struct MiniPlayerView: View {
    @Binding var showPlayer: Bool
    @ObservedObject private var player = PlayerService.shared

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { showPlayer = true }) {
                HStack(spacing: 10) {
                    ArtworkView(urlString: player.current?.meta.picUrl, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.displayName ?? "")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Text(player.current?.displaySinger ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if player.isLoading {
                ProgressView().padding(.horizontal, 2)
            }
            Button(action: { player.toggle() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.borderless)
            Button(action: { player.next() }) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
    }
}

extension View {
    func hideKeyboardOnScroll() -> some View { self }
}
