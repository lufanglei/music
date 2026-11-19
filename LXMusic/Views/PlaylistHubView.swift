import SwiftUI
import UIKit

/// 「歌单」页：上半部分是推荐歌单（各地区官方榜单），下半部分是用户自己建的歌单。
struct PlaylistHubView: View {
    @EnvironmentObject var library: LibraryStore

    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var renameTarget: Playlist?
    @State private var renameName = ""

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    chartSection
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
                .padding(.top, 8)
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
        }
    }

    // MARK: - 推荐歌单

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("推荐歌单", subtitle: "Apple Music 各地区热门榜单 · 每日更新")

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ChartPlaylist.all) { chart in
                    NavigationLink {
                        ChartDetailView(chart: chart)
                    } label: {
                        ChartCard(chart: chart)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 我的歌单

    private var myPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("我的歌单", subtitle: "\(library.playlists.count) 个 · 长按可重命名或删除")

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
        Text("推荐歌单来自 Apple 官方榜单，播放使用官方试听片段；在「设置 → 音源管理」导入洛雪音源脚本后，同一批歌曲会改用脚本返回的播放地址。")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 2)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 推荐歌单卡片

struct ChartCard: View {
    let chart: ChartPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: chart.colors.map { Color(hex: $0) },
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 92, height: 92)
                    .offset(x: 58, y: -26)
                Image(systemName: chart.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.leading, 14)
                    .padding(.bottom, 20)
            }
            .frame(height: 104)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(chart.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(chart.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
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

struct ChartDetailView: View {
    @EnvironmentObject var library: LibraryStore
    let chart: ChartPlaylist

    @State private var songs: [MusicInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
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
                        Text("正在获取榜单…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(chart.title)
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
            ZStack {
                LinearGradient(colors: chart.colors.map { Color(hex: $0) },
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Image(systemName: chart.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(chart.title)
                    .font(.headline)
                Text(chart.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(songs.isEmpty ? "Apple Music 官方榜单" : "\(songs.count) 首 · Apple Music 官方榜单")
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
        ChartService.shared.songs(for: chart, force: force) { result in
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
        let shuffled = songs.shuffled()
        PlayerService.shared.playAll(shuffled)
    }

    private func saveAllToNewPlaylist() {
        guard !songs.isEmpty else { return }
        let name = "\(chart.title)"
        library.createPlaylist(name: name)
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
