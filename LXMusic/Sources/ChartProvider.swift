import Foundation

/// 「歌单广场」的推荐歌单：各地区 Apple Music 热门榜单。
///
/// 为什么用这个数据源：
///  - 洛雪的「歌单 / 排行榜」来自内置平台 API（kw/kg/tx/wy/mg），那些接口在本工程里没有内置；
///  - Apple Marketing Tools RSS 是官方公开接口，无需密钥、按地区区分、每日更新，
///    条目里的 `id` 就是 iTunes trackId，可以直接被音源脚本换成播放链接；
///  - 不需要用户登录，也不依赖第三方聚合服务，不会因为某个私有接口失效而整块功能挂掉。
struct ChartPlaylist: Identifiable, Hashable {
    let storefront: String
    let title: String
    let subtitle: String
    let symbol: String
    /// 封面渐变，十六进制色值
    let colors: [String]

    var id: String { "chart_\(storefront)" }

    /// 两个域名指向同一份数据，实测会交替超时，请求时轮换使用
    static let hosts = [
        "https://rss.applemarketingtools.com",
        "https://rss.marketingtools.apple.com",
    ]

    func feedURL(host: String) -> String {
        "\(host)/api/v2/\(storefront)/music/most-played/50/songs.json"
    }

    static let all: [ChartPlaylist] = [
        ChartPlaylist(storefront: "cn",
                      title: "中国大陆热歌榜",
                      subtitle: "华语流行风向",
                      symbol: "music.note",
                      colors: ["E23E57", "88304E"]),
        ChartPlaylist(storefront: "hk",
                      title: "中国香港热歌榜",
                      subtitle: "粤语与港乐",
                      symbol: "music.mic",
                      colors: ["F7971E", "C46B00"]),
        ChartPlaylist(storefront: "us",
                      title: "美国热歌榜",
                      subtitle: "Billboard 同源热度",
                      symbol: "globe.americas.fill",
                      colors: ["2B5876", "4E4376"]),
        ChartPlaylist(storefront: "jp",
                      title: "日本热歌榜",
                      subtitle: "J-Pop 与动漫",
                      symbol: "sparkles",
                      colors: ["FF5F6D", "C0392B"]),
        ChartPlaylist(storefront: "kr",
                      title: "韩国热歌榜",
                      subtitle: "K-Pop 热单",
                      symbol: "waveform",
                      colors: ["A18CD1", "6C5CE7"]),
        ChartPlaylist(storefront: "gb",
                      title: "英国热歌榜",
                      subtitle: "英伦流行",
                      symbol: "crown.fill",
                      colors: ["1D976C", "117A65"]),
    ]
}

enum ChartError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badResponse: return "榜单数据解析失败，请稍后重试"
        }
    }
}

/// 榜单拉取与转换。结果按 storefront 缓存，避免每次进入歌单都重新请求。
final class ChartService {
    static let shared = ChartService()

    private var cache: [String: (songs: [MusicInfo], date: Date)] = [:]
    private let cacheLifetime: TimeInterval = 60 * 30

    func songs(for chart: ChartPlaylist,
               force: Bool = false,
               completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        if !force,
           let hit = cache[chart.storefront],
           Date().timeIntervalSince(hit.date) < cacheLifetime,
           !hit.songs.isEmpty {
            completion(.success(hit.songs))
            return
        }

        fetch(chart, attempt: 0, completion: completion)
    }

    /// 最多尝试 3 次，每次换一个域名；单次超时压到 15 秒，避免用户干等。
    private func fetch(_ chart: ChartPlaylist,
                       attempt: Int,
                       completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let maxAttempts = 3
        let host = ChartPlaylist.hosts[attempt % ChartPlaylist.hosts.count]
        guard let url = URL(string: chart.feedURL(host: host)) else {
            completion(.failure(ChartError.badResponse))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LXMusic-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let isLast = attempt + 1 >= maxAttempts
        let fail: (Error) -> Void = { error in
            DispatchQueue.main.async { completion(.failure(error)) }
        }
        let retry: () -> Void = { [weak self] in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self?.fetch(chart, attempt: attempt + 1, completion: completion)
            }
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                if isLast { fail(error) } else { retry() }
                return
            }
            guard let data = data,
                  let songs = Self.parse(data, storefront: chart.storefront),
                  !songs.isEmpty else {
                if isLast { fail(ChartError.badResponse) } else { retry() }
                return
            }
            // 缓存只在主线程读写，避免多线程同时改同一个 Dictionary
            DispatchQueue.main.async {
                self?.cache[chart.storefront] = (songs, Date())
                completion(.success(songs))
            }
        }.resume()
    }

    /// RSS 结构：{ feed: { results: [ { id, name, artistName, artworkUrl100, releaseDate } ] } }
    /// 用 JSONSerialization 而不是 Codable：不同地区返回的 id 有时是字符串有时是数字。
    static func parse(_ data: Data, storefront: String) -> [MusicInfo]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let feed = root["feed"] as? [String: Any],
              let results = feed["results"] as? [[String: Any]] else {
            return nil
        }
        return results.enumerated().compactMap { index, item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let trackId = (item["id"] as? String)
                ?? (item["id"] as? NSNumber)?.stringValue
                ?? "\(storefront)-\(index)"
            let artist = item["artistName"] as? String ?? ""
            let artwork = MusicInfo.hdArtwork(item["artworkUrl100"] as? String)
            var raw = item
            raw["source"] = "itunes"
            raw["storefront"] = storefront
            return MusicInfo.make(id: "itunes_\(trackId)",
                                  name: name,
                                  singer: artist,
                                  source: "itunes",
                                  songId: trackId,
                                  picUrl: artwork,
                                  raw: raw)
        }
    }
}
