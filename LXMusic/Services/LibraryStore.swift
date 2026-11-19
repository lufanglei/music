import Foundation

/// 「我的列表」本地持久化，对应洛雪的列表机制
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var playlists: [Playlist] = []
    @Published var localMusics: [MusicInfo] = []

    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lx-library.json")
    }

    private struct Store: Codable {
        var playlists: [Playlist]
        var localMusics: [MusicInfo]
    }

    func load() {
        if let data = try? Data(contentsOf: storeURL),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            playlists = store.playlists
            localMusics = store.localMusics
        }
        if !playlists.contains(where: { $0.name == "我喜欢的" }) {
            playlists.insert(Playlist.new(name: "我喜欢的"), at: 0)
        }
        if playlists.isEmpty {
            playlists.append(Playlist.new(name: "试听列表"))
        }
        save()
    }

    func save() {
        let store = Store(playlists: playlists, localMusics: localMusics)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    var favoritesID: String? { playlists.first(where: { $0.name == "我喜欢的" })?.id }

    func isFavorite(_ music: MusicInfo) -> Bool {
        guard let id = favoritesID,
              let list = playlists.first(where: { $0.id == id }) else { return false }
        return list.musics.contains(where: { $0.id == music.id })
    }

    func toggleFavorite(_ music: MusicInfo) {
        guard let id = favoritesID,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        if let musicIndex = playlists[index].musics.firstIndex(where: { $0.id == music.id }) {
            playlists[index].musics.remove(at: musicIndex)
        } else {
            playlists[index].musics.insert(music, at: 0)
        }
        save()
    }

    func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.append(Playlist.new(name: trimmed))
        save()
    }

    func renamePlaylist(id: String, name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        playlists[index].name = name
        save()
    }

    func deletePlaylist(id: String) {
        guard playlists.first(where: { $0.id == id })?.name != "我喜欢的" else { return }
        playlists.removeAll { $0.id == id }
        save()
    }

    func add(_ music: MusicInfo, to playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !playlists[index].musics.contains(where: { $0.id == music.id }) else { return }
        playlists[index].musics.append(music)
        save()
    }

    func add(_ musics: [MusicInfo], to playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existing = Set(playlists[index].musics.map { $0.id })
        playlists[index].musics.append(contentsOf: musics.filter { !existing.contains($0.id) })
        save()
    }

    func remove(musicID: String, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].musics.removeAll { $0.id == musicID }
        save()
    }

    func addLocal(_ music: MusicInfo) {
        guard !localMusics.contains(where: { $0.id == music.id }) else { return }
        localMusics.insert(music, at: 0)
        if let id = favoritesID { add(music, to: id) }
        save()
    }

    func removeLocal(_ music: MusicInfo) {
        localMusics.removeAll { $0.id == music.id }
        for index in playlists.indices {
            playlists[index].musics.removeAll { $0.id == music.id }
        }
        if let path = music.meta.filePath { try? FileManager.default.removeItem(atPath: path) }
        if let pic = music.meta.picUrl, FileManager.default.fileExists(atPath: pic) {
            try? FileManager.default.removeItem(atPath: pic)
        }
        save()
    }
}
