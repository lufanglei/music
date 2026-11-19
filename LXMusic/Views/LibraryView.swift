import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var showImporter = false
    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showImporter = true } label: {
                        Label("从「文件」App 导入音频", systemImage: "square.and.arrow.down")
                    }
                    Button { scanSharedDocuments() } label: {
                        Label("扫描 Finder 文件共享目录", systemImage: "doc.on.doc")
                    }
                    if let importMessage = importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(library.localMusics) { music in
                        SongRow(music: music) {
                            PlayerService.shared.play(music, in: library.localMusics)
                        }
                    }
                    .onDelete { offsets in
                        offsets.compactMap { library.localMusics.indices.contains($0) ? library.localMusics[$0] : nil }
                            .forEach { library.removeLocal($0) }
                    }
                } header: {
                    Text("本地音乐 · \(library.localMusics.count)")
                } footer: {
                    Text("支持 MP3 / M4A / FLAC / WAV 等，会读取内嵌标题、歌手与封面，并复制到 App 沙盒以便长期播放。")
                }

                Section {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id)
                        } label: {
                            HStack {
                                Image(systemName: playlist.name == "我喜欢的" ? "heart.fill" : "music.note.list")
                                    .foregroundColor(playlist.name == "我喜欢的" ? .pink : .accentColor)
                                    .frame(width: 24)
                                Text(playlist.name)
                                Spacer()
                                Text("\(playlist.musics.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.compactMap { library.playlists.indices.contains($0) ? library.playlists[$0].id : nil }
                            .forEach { library.deletePlaylist(id: $0) }
                    }
                    Button {
                        newName = ""
                        showNewPlaylist = true
                    } label: {
                        Label("新建列表", systemImage: "plus")
                    }
                } header: {
                    Text("我的列表")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的音乐")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .alert("新建列表", isPresented: $showNewPlaylist) {
                TextField("列表名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建") {
                    library.createPlaylist(name: newName)
                    newName = ""
                }
            } message: {
                Text("创建一个本地歌单，可把搜索结果或本地歌曲加进去。")
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var count = 0
            let group = DispatchGroup()
            for url in urls {
                group.enter()
                LocalMusicImporter.importFile(from: url) { value in
                    DispatchQueue.main.async {
                        if case .success(let music) = value {
                            library.addLocal(music)
                            count += 1
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                importMessage = "已导入 \(count) 首本地歌曲"
            }
        case .failure(let error):
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func scanSharedDocuments() {
        importMessage = "正在扫描…"
        LocalMusicImporter.scanDocuments { list in
            list.forEach { library.addLocal($0) }
            importMessage = "扫描完成，新增 \(list.count) 首"
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var library: LibraryStore
    let playlistID: String

    @State private var showRename = false
    @State private var renameName = ""

    private var playlist: Playlist? { library.playlists.first { $0.id == playlistID } }
    private var isFavoriteList: Bool { playlist?.name == "我喜欢的" }

    var body: some View {
        List {
            if let playlist = playlist {
                Section {
                    header(playlist)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    if playlist.musics.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("歌单还是空的")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("去「发现」搜索歌曲，或在「歌单 → 推荐歌单」里打开一个榜单，长按歌曲选择「添加到歌单」。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button { PlayerService.shared.playAll(playlist.musics) } label: {
                            Label("播放全部（\(playlist.musics.count) 首）", systemImage: "play.fill")
                        }
                        Button { PlayerService.shared.playAll(playlist.musics.shuffled()) } label: {
                            Label("随机播放", systemImage: "shuffle")
                        }
                        ForEach(Array(playlist.musics.enumerated()), id: \.element.id) { index, music in
                            SongRow(music: music, index: index + 1) {
                                PlayerService.shared.play(music, in: playlist.musics)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.compactMap {
                                playlist.musics.indices.contains($0) ? playlist.musics[$0].id : nil
                            }
                            ids.forEach { library.remove(musicID: $0, from: playlistID) }
                        }
                        .onMove { source, destination in
                            library.moveMusic(in: playlistID, from: source, to: destination)
                        }
                    }
                } header: {
                    Text("\(playlist.musics.count) 首")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(playlist?.name ?? "歌单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    if (playlist?.musics.count ?? 0) > 1 {
                        EditButton()
                    }
                    Menu {
                        Button {
                            renameName = playlist?.name ?? ""
                            showRename = true
                        } label: {
                            Label("重命名歌单", systemImage: "pencil")
                        }
                        if !isFavoriteList {
                            Button(role: .destructive) {
                                library.deletePlaylist(id: playlistID)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $renameName)
            Button("取消", role: .cancel) {}
            Button("保存") { library.renamePlaylist(id: playlistID, name: renameName) }
        }
    }

    private func header(_ playlist: Playlist) -> some View {
        HStack(spacing: 14) {
            PlaylistCover(musics: playlist.musics,
                          symbol: isFavoriteList ? "heart.fill" : "music.note.list",
                          highlighted: isFavoriteList)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(playlist.musics.isEmpty ? "空歌单" : "\(playlist.musics.count) 首歌曲")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("创建于 \(Self.dateString(playlist.createdAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private static func dateString(_ stamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: stamp))
    }
}
