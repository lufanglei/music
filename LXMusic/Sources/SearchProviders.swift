import Foundation

enum SearchError: LocalizedError {
    case emptyKeyword
    case missingURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .emptyKeyword: return "请输入搜索关键词"
        case .missingURL: return "请先在设置里填写自定义搜索接口地址"
        case .badResponse: return "搜索接口返回的数据无法解析"
        }
    }
}

enum NetworkJSON {
    static func get(_ urlString: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(LXError.invalidResponse))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let object = try? JSONSerialization.jsonObject(with: data) else {
                    completion(.failure(SearchError.badResponse))
                    return
                }
                completion(.success(object))
            }
        }.resume()
    }
}

/// 搜索服务。洛雪桌面版的搜索由内置 musicSdk（kw/kg/tx/wy/mg）提供，
/// 那些接口未在本工程内置；这里提供两种可立即使用的来源，并留出自定义接口：
///  1. Apple 官方 iTunes Search API（合规、稳定、全球曲库）
///  2. 自定义 HTTP 接口（可指向自建聚合服务，返回洛雪风格歌曲数组）
final class SearchService {
    static let shared = SearchService()

    func search(keyword: String,
                page: Int = 0,
                completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(SearchError.emptyKeyword))
            return
        }
        switch SettingsStore.shared.searchMode {
        case .itunes:
            ITunesSearchProvider.search(keyword: trimmed, page: page, completion: completion)
        case .custom:
            CustomSearchProvider.search(keyword: trimmed, page: page, completion: completion)
        }
    }

    static let hotKeywords: [String] = [
        "周杰伦", "陈奕迅", "邓紫棋", "林俊杰", "五月天",
        "Taylor Swift", "Ed Sheeran", "Lo-Fi", "钢琴", "国风",
    ]
}

// MARK: - Apple 官方曲库

enum ITunesSearchProvider {
    /// 一次取满 200 条（iTunes Search 不支持 offset 翻页，只认 limit），
    /// 之后由本地切片实现「加载更多」，避免每次翻页都打一次接口。
    private static let pageSize = 50
    private static let fetchLimit = 200
    private static var cache: [String: (songs: [MusicInfo], date: Date)] = [:]
    private static let cacheLifetime: TimeInterval = 60 * 10

    static func search(keyword: String,
                       page: Int,
                       completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let cacheKey = keyword.lowercased()

        if let hit = cache[cacheKey],
           Date().timeIntervalSince(hit.date) < cacheLifetime {
            completion(.success(slice(hit.songs, page: page)))
            return
        }

        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(SearchError.badResponse))
            return
        }

        // 关键：iTunes 的 cn storefront 搜索接口已不返回结果，中文关键词在 us 区也不稳定。
        // 实测中港台区对中文支持最好，英文则走美/英区。
        let stores = storefronts(for: keyword)
        attempt(encoded: encoded,
                stores: stores,
                index: 0,
                original: keyword,
                page: page,
                completion: completion)
    }

    private static func attempt(encoded: String,
                                stores: [String],
                                index: Int,
                                original: String,
                                page: Int,
                                completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        guard index < stores.count else {
            completion(.success([]))
            return
        }
        let url = "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=\(fetchLimit)&country=\(stores[index])"
        NetworkJSON.get(url) { result in
            switch result {
            case .success(let value):
                let songs = parse(value)
                if songs.isEmpty {
                    attempt(encoded: encoded,
                            stores: stores,
                            index: index + 1,
                            original: original,
                            page: page,
                            completion: completion)
                } else {
                    cache[original.lowercased()] = (songs, Date())
                    completion(.success(slice(songs, page: page)))
                }
            case .failure(let error):
                if index == stores.count - 1 {
                    completion(.failure(error))
                } else {
                    attempt(encoded: encoded,
                            stores: stores,
                            index: index + 1,
                            original: original,
                            page: page,
                            completion: completion)
                }
            }
        }
    }

    /// 中文/日文/韩文优先中港台区，其余走美英区
    static func storefronts(for keyword: String) -> [String] {
        let hasCJK = keyword.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) ||   // 日文假名
            (0x3400...0x4DBF).contains(scalar.value) ||   // 中文扩展 A
            (0x4E00...0x9FFF).contains(scalar.value) ||   // 中文基本区
            (0xAC00...0xD7AF).contains(scalar.value)      // 韩文
        }
        return hasCJK ? ["tw", "hk", "us"] : ["us", "gb"]
    }

    private static func slice(_ songs: [MusicInfo], page: Int) -> [MusicInfo] {
        let start = page * pageSize
        guard start < songs.count else { return [] }
        let end = min(start + pageSize, songs.count)
        return Array(songs[start..<end])
    }

    static func parse(_ value: Any) -> [MusicInfo] {
        guard let dict = value as? [String: Any],
              let results = dict["results"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return results.compactMap { item in
            guard let name = item["trackName"] as? String else { return nil }
            let id = (item["trackId"] as? NSNumber)?.stringValue
                ?? (item["trackId"] as? String)
                ?? UUID().uuidString
            guard seen.insert(id).inserted else { return nil }
            let singer = item["artistName"] as? String ?? ""
            let album = item["collectionName"] as? String ?? ""
            let pic = MusicInfo.hdArtwork(item["artworkUrl100"] as? String)
            let millis = (item["trackTimeMillis"] as? NSNumber)?.doubleValue ?? 0
            let interval = millis > 0 ? MusicInfo.formatInterval(millis / 1000) : nil
            return MusicInfo.make(id: "itunes_" + id,
                                  name: name,
                                  singer: singer,
                                  source: "itunes",
                                  interval: interval,
                                  songId: id,
                                  albumName: album,
                                  picUrl: pic,
                                  raw: item)
        }
    }
}

// MARK: - 自定义 HTTP 搜索接口

enum CustomSearchProvider {
    static func search(keyword: String,
                       page: Int,
                       completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let template = SettingsStore.shared.customSearchURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            completion(.failure(SearchError.missingURL))
            return
        }
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        var urlString = template
            .replacingOccurrences(of: "{keyword}", with: encoded)
            .replacingOccurrences(of: "{page}", with: "\(page)")
            .replacingOccurrences(of: "{limit}", with: "50")
        if !template.contains("{keyword}") {
            urlString += (urlString.contains("?") ? "&" : "?") + "keyword=\(encoded)&page=\(page)"
        }
        NetworkJSON.get(urlString) { result in
            completion(result.map { CustomSearchProvider.parse($0) })
        }
    }

    static func parse(_ value: Any) -> [MusicInfo] {
        let items: [[String: Any]]
        if let array = value as? [[String: Any]] {
            items = array
        } else if let dict = value as? [String: Any] {
            var found: [[String: Any]]?
            for key in ["data", "list", "songs", "results", "rows", "items", "musicList"] {
                if let array = dict[key] as? [[String: Any]] { found = array; break }
                if let nested = dict[key] as? [String: Any],
                   let array = nested["list"] as? [[String: Any]] { found = array; break }
            }
            items = found ?? []
        } else {
            items = []
        }
        return items.compactMap { flexible($0, defaultSource: "custom") }
    }

    /// 尽量宽松地解析第三方接口返回的字段，并把原始对象完整保留给音源脚本
    static func flexible(_ item: [String: Any], defaultSource: String) -> MusicInfo? {
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if let value = item[key] as? String, !value.isEmpty { return value }
                if let number = item[key] as? NSNumber { return number.stringValue }
            }
            return nil
        }
        guard let name = string(["name", "title", "songName", "musicName", "trackName", "song"]) else {
            return nil
        }
        let singer = string(["singer", "artist", "artistName", "author", "singers", "artists"]) ?? ""
        let source = string(["source", "platform", "origin", "from"]) ?? defaultSource
        let songId = string(["songId", "id", "songmid", "trackId", "hash", "copyrightId", "rid", "mid"])
        let albumName = string(["albumName", "album", "collectionName", "albumTitle"]) ?? ""
        let picUrl = string(["picUrl", "pic", "cover", "coverUrl", "artworkUrl100", "albumPic", "img"])
        var interval = string(["interval", "durationLabel", "time"])
        if interval == nil,
           let seconds = item["duration"] as? NSNumber,
           seconds.doubleValue > 0 {
            interval = MusicInfo.formatInterval(seconds.doubleValue > 10000
                                                ? seconds.doubleValue / 1000
                                                : seconds.doubleValue)
        }
        let id = songId.map { "\(source)_\($0)" } ?? "\(source)_\(name)_\(singer)"
        return MusicInfo.make(id: id,
                              name: name,
                              singer: singer,
                              source: source,
                              interval: interval,
                              songId: songId,
                              albumName: albumName,
                              picUrl: picUrl,
                              raw: item)
    }
}
