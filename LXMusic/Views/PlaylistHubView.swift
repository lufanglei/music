import SwiftUI
import UIKit

/// 「歌单」页：顶部切换榜单来源，下面是该来源的完整榜单列表，最后是用户自己建的歌单。
///
/// 与桌面版对齐：桌面左侧的「音乐来源」下拉（酷狗 / QQ / 网易云 / Apple）+ 每个来源下的
/// 一长串榜单，这里用同样的结构呈现，只是把下拉换成了横向胶囊。
struct PlaylistHubView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sources: SourceManager

    @State private var platform: BoardPlatform = .apple
    @State private var catalogs: [BoardPlatform: [MusicBoard]] = [:]
    @State private var loadingPlatforms: Set<BoardPlatform> = []
    @State private var errors: [BoardPlatform: String] = [:]

    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var renameTarget: Playlist?
    @State private var renameName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    platformPicker
                    boardSection
                    myPlaylistsSection
                    footer
                }
                // 两个 alert 挂在不同的视图上：同一个视图挂多个 alert 时，iOS 只会响应最后一个
                .alert("新建歌单", isPresented: $showNewPlaylist) {
                    TextField("歌单名称", text: $newName)
                    Button("取消", role: .cancel) { newName = "" }
                    Button("创建") {
                        library.createPlaylist(name: newName)
                        newName = ""
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("歌单")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newName = ""
                        showNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("重命名歌单",
                   isPresented: Binding(get: { renameTarget != nil },
                                        set: { if !$0 { renameTarget = nil } })) {
                TextField("歌单名称", text: $renameName)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("保存") {
                    if let target = renameTarget {
                        library.renamePlaylist(id: target.id, name: renameName)
                    }
                    renameTarget = nil
                }
            }
            .task { loadCatalog(for: platform) }
        }
    }

    // MARK: - 来源切换

    private var platformPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BoardPlatform.allCases) { item in
                    Button {
                        guard platform != item else { return }
                        platform = item
                        loadCatalog(for: item)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isReady(item) ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(item.displayName)
                                .font(.subheadline)
                                .fontWeight(platform == item ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(platform == item
                                           ? Color.accentColor.opacity(0.16)
                                           : Color(UIColor.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Capsule().stroke(platform == item ? Color.accentColor.opacity(0.45) : Color.clear,
                                             lineWidth: 1)
                        )
                        .foregroundColor(platform == item ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 榜单列表

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(platform == .apple ? "官方热歌榜" : "\(platform.displayName)榜单")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if let boards = catalogs[platform], !boards.isEmpty {
                    Text("\(boards.count) 个")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !isReady(platform) {
                sourceHint
            }

            if let boards = catalogs[platform], !boards.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                        NavigationLink {
                            BoardDetailView(board: board)
                        } label: {
                            BoardRow(board: board, ready: isReady(board.platform))
                        }
                        .buttonStyle(.plain)

                        if index < boards.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if loadingPlatforms.contains(platform) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在获取榜单目录…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 14)
            } else if let message = errors[platform] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("重新加载") { loadCatalog(for: platform, force: true) }
                        .font(.subheadline)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var sourceHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundColor(.orange)
                .padding(.top, 1)
            Text(platform == .apple
                 ? "还没有可用的 Apple 试听音源。到「设置 → 音源管理」安装示例源后即可播放。"
                 : "还没导入\(platform.displayName)音源：榜单可以浏览，点播放会提示导入。到「设置 → 音源管理」粘贴对应音源脚本即可。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 我的歌单

    private var myPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("我的歌单")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(library.playlists.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(library.playlists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist,
                                    index: index,
                                    isFavoriteList: playlist.name == "我喜欢的")
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameName = playlist.name
                            renameTarget = playlist
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        if playlist.name != "我喜欢的" {
                            Button(role: .destructive) {
                                library.deletePlaylist(id: playlist.id)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                    }

                    if index < library.playlists.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }

                Divider().padding(.leading, 68)

                Button {
                    newName = ""
                    showNewPlaylist = true
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.accentColor))
                        Text("新建歌单")
                            .font(.body)
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var footer: some View {
        Text("榜单目录与曲目来自各平台公开接口，Apple 榜单来自 Apple 官方 RSS。播放仍由你导入的洛雪音源脚本取链接：酷狗榜单需要声明 kg 的音源，QQ 音乐需要 tx，网易云需要 wy。")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 2)
    }

    // MARK: - 逻辑

    private func isReady(_ platform: BoardPlatform) -> Bool {
        if let key = platform.sourceKey {
            return sources.capabilities[key] != nil
        }
        return sources.capabilities["itunes"] != nil
    }

    private func loadCatalog(for platform: BoardPlatform, force: Bool = false) {
        if !force, catalogs[platform] != nil { return }
        guard !loadingPlatforms.contains(platform) else { return }
        loadingPlatforms.insert(platform)
        errors[platform] = nil
        BoardService.shared.catalog(for: platform, force: force) { result in
            loadingPlatforms.remove(platform)
            switch result {
            case .success(let boards):
                catalogs[platform] = boards
            case .failure(let error):
                errors[platform] = "加载失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 榜单行

struct BoardRow: View {
    let board: MusicBoard
    let ready: Bool

    var body: some View {
        HStack(spacing: 12) {
            BoardCover(board: board, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(board.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !ready {
                Text("需音源")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// 榜单封面：有真实的榜单图就用图，没有则用渐变 + 图标兜底
struct BoardCover: View {
    let board: MusicBoard
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            LinearGradient(colors: board.colors.map { Color(hex: $0) },
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            Image(systemName: board.platform.placeholderSymbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            if let urlString = board.coverURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}

// MARK: - 我的歌单行

struct PlaylistRow: View {
    let playlist: Playlist
    let index: Int
    let isFavoriteList: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlaylistCover(musics: playlist.musics,
                          symbol: isFavoriteList ? "heart.fill" : "music.note.list",
                          seed: index,
                          highlighted: isFavoriteList)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(playlist.musics.isEmpty ? "空歌单" : "\(playlist.musics.count) 首")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 歌单封面：有封面时用前四首拼成 2×2，没有则显示渐变 + 图标
struct PlaylistCover: View {
    let musics: [MusicInfo]
    var symbol: String = "music.note.list"
    var seed: Int = 0
    var highlighted: Bool = false

    private var pics: [String?] {
        Array(musics.prefix(4).map { $0.meta.picUrl })
    }

    var body: some View {
        Group {
            if pics.isEmpty {
                placeholder
            } else {
                mosaic
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var mosaic: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let filled = pics + Array(repeating: nil, count: max(0, 4 - pics.count))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cell(filled[0], size: half)
                    cell(filled[1], size: half)
                }
                HStack(spacing: 0) {
                    cell(filled[2], size: half)
                    cell(filled[3], size: half)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ url: String?, size: CGFloat) -> some View {
        if let url = url, !url.isEmpty {
            ArtworkView(urlString: url, size: size, cornerRadius: 0)
        } else {
            Color(UIColor.tertiarySystemFill)
                .frame(width: size, height: size)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: highlighted
                           ? [Color.pink.opacity(0.85), Color.purple.opacity(0.75)]
                           : [Color(hex: "4A6CF7"), Color(hex: "8E54E9")],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

// MARK: - 榜单详情

struct BoardDetailView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sources: SourceManager
    let board: MusicBoard

    @State private var songs: [MusicInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var platformReady: Bool {
        guard let key = board.platform.sourceKey else {
            return sources.capabilities["itunes"] != nil
        }
        return sources.capabilities[key] != nil
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if !platformReady {
                Section {
                    Text(board.platform == .apple
                         ? "当前没有可用的 Apple 试听音源，播放会失败。到「设置 → 音源管理」安装示例源。"
                         : "还没导入\(board.platform.displayName)音源，点播放会提示导入。到「设置 → 音源管理」粘贴对应脚本后回来即可播放完整歌曲。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage = errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重新加载") { load(force: true) }
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !songs.isEmpty {
                Section {
                    Button { PlayerService.shared.playAll(songs) } label: {
                        Label("播放全部（\(songs.count) 首）", systemImage: "play.fill")
                    }
                    Button { playShuffled() } label: {
                        Label("随机播放", systemImage: "shuffle")
                    }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, music in
                        SongRow(music: music, index: index + 1) {
                            PlayerService.shared.play(music, in: songs)
                        }
                    }
                } header: {
                    Text("榜单曲目")
                }
            } else if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在获取榜单曲目…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(board.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        saveAllToNewPlaylist()
                    } label: {
                        Label("全部加入新歌单", systemImage: "plus.rectangle.on.folder")
                    }
                    Button { load(force: true) } label: {
                        Label("刷新榜单", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(songs.isEmpty)
            }
        }
        .task { load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BoardCover(board: board, size: 96)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(board.title)
                    .font(.headline)
                Text(board.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(songs.isEmpty
                     ? board.platform.displayName
                     : "\(songs.count) 首 · \(board.platform.displayName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func load(force: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        BoardService.shared.songs(for: board, force: force) { result in
            isLoading = false
            switch result {
            case .success(let list):
                songs = list
            case .failure(let error):
                if songs.isEmpty {
                    errorMessage = "加载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func playShuffled() {
        guard !songs.isEmpty else { return }
        PlayerService.shared.playAll(songs.shuffled())
    }

    private func saveAllToNewPlaylist() {
        guard !songs.isEmpty else { return }
        library.createPlaylist(name: board.title)
        guard let target = library.playlists.last else { return }
        library.add(songs, to: target.id)
    }
}

// MARK: - 十六进制颜色

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
