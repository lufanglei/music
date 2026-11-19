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
    static func search(keyword: String,
                       page: Int,
                       completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(SearchError.badResponse))
            return
        }
        let url = "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=50&offset=\(page * 50)&country=cn"
        NetworkJSON.get(url) { result in
            switch result {
            case .success(let value):
                let songs = parse(value)
                if songs.isEmpty, page == 0 {
                    // 部分地区曲库为空时回退到全球区
                    let fallback = url.replacingOccurrences(of: "country=cn", with: "country=us")
                    NetworkJSON.get(fallback) { fallbackResult in
                        completion(fallbackResult.map { ITunesSearchProvider.parse($0) })
                    }
                } else {
                    completion(.success(songs))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func parse(_ value: Any) -> [MusicInfo] {
        guard let dict = value as? [String: Any],
              let results = dict["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let name = item["trackName"] as? String else { return nil }
            let id = (item["trackId"] as? NSNumber)?.stringValue ?? UUID().uuidString
            let singer = item["artistName"] as? String ?? ""
            let album = item["collectionName"] as? String ?? ""
            let pic = (item["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100", with: "600x600")
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
