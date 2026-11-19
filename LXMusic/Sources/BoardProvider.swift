import Foundation

/// 榜单来源，对应桌面版左侧「音乐来源」下拉里的那几项。
///
/// 取舍说明：
///  - 洛雪桌面端的榜单来自内置平台接口（kw/kg/tx/wy/mg），自定义源协议本身**不提供**榜单能力，
///    所以这里直接对接各平台公开的榜单接口，拿到与桌面端同名的榜单和真实曲目；
///  - 歌曲里的 `source` 字段保持 `kg / tx / wy`，播放时仍交给用户导入的洛雪音源脚本取链接，
///    与「App 只做播放器框架 + 音源由脚本提供」的分工一致；
///  - Apple 官方榜保留，作为不需要任何音源脚本就能播的兜底。
enum BoardPlatform: String, CaseIterable, Identifiable, Hashable {
    case apple
    case kg
    case tx
    case wy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple 官方榜"
        case .kg: return "酷狗音乐"
        case .tx: return "QQ 音乐"
        case .wy: return "网易云音乐"
        }
    }

    var shortName: String {
        switch self {
        case .apple: return "苹果"
        case .kg: return "酷狗"
        case .tx: return "QQ"
        case .wy: return "网易"
        }
    }

    /// 播放这个榜单的歌曲需要的音源 key（Apple 榜由内置试听源处理，没有平台 key）
    var sourceKey: String? {
        switch self {
        case .apple: return nil
        case .kg: return "kg"
        case .tx: return "tx"
        case .wy: return "wy"
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .apple: return "applelogo"
        case .kg: return "music.note"
        case .tx: return "waveform"
        case .wy: return "cloud.fill"
        }
    }
}

/// 榜单的取数方式
enum BoardEndpoint: Hashable {
    case apple(storefront: String)
    case kugou(rankId: String)
    case qq(topId: String)
    case netease(playlistId: String)
}

struct MusicBoard: Identifiable, Hashable {
    let id: String
    let platform: BoardPlatform
    let title: String
    let subtitle: String
    let coverURL: String?
    /// 无封面时的兜底渐变
    let colors: [String]
    let endpoint: BoardEndpoint
}

enum BoardError: LocalizedError {
    case badResponse
    case empty

    var errorDescription: String? {
        switch self {
        case .badResponse: return "榜单数据获取失败，请检查网络后重试"
        case .empty: return "这个榜单暂时没有曲目"
        }
    }
}

// MARK: - Apple 官方榜（无需音源脚本即可播放试听）

extension MusicBoard {
    static let appleBoards: [MusicBoard] = [
        MusicBoard(id: "apple_cn", platform: .apple,
                   title: "中国大陆热歌榜", subtitle: "华语流行风向",
                   coverURL: nil, colors: ["E23E57", "88304E"],
                   endpoint: .apple(storefront: "cn")),
        MusicBoard(id: "apple_hk", platform: .apple,
                   title: "中国香港热歌榜", subtitle: "粤语与港乐",
                   coverURL: nil, colors: ["F7971E", "C46B00"],
                   endpoint: .apple(storefront: "hk")),
        MusicBoard(id: "apple_tw", platform: .apple,
                   title: "中国台湾热歌榜", subtitle: "华语与台语",
                   coverURL: nil, colors: ["00B4DB", "0083B0"],
                   endpoint: .apple(storefront: "tw")),
        MusicBoard(id: "apple_us", platform: .apple,
                   title: "美国热歌榜", subtitle: "Billboard 同源热度",
                   coverURL: nil, colors: ["2B5876", "4E4376"],
                   endpoint: .apple(storefront: "us")),
        MusicBoard(id: "apple_jp", platform: .apple,
                   title: "日本热歌榜", subtitle: "J-Pop 与动漫",
                   coverURL: nil, colors: ["FF5F6D", "C0392B"],
                   endpoint: .apple(storefront: "jp")),
        MusicBoard(id: "apple_kr", platform: .apple,
                   title: "韩国热歌榜", subtitle: "K-Pop 热单",
                   coverURL: nil, colors: ["A18CD1", "6C5CE7"],
                   endpoint: .apple(storefront: "kr")),
        MusicBoard(id: "apple_gb", platform: .apple,
                   title: "英国热歌榜", subtitle: "英伦流行",
                   coverURL: nil, colors: ["1D976C", "117A65"],
                   endpoint: .apple(storefront: "gb")),
        MusicBoard(id: "apple_fr", platform: .apple,
                   title: "法国热歌榜", subtitle: "法语流行",
                   coverURL: nil, colors: ["4568DC", "B06AB3"],
                   endpoint: .apple(storefront: "fr")),
    ]
}

// MARK: - 榜单服务

final class BoardService {
    static let shared = BoardService()
    private init() {}

    private var catalogCache: [BoardPlatform: (boards: [MusicBoard], date: Date)] = [:]
    private var songCache: [String: (songs: [MusicInfo], date: Date)] = [:]
    private let catalogLifetime: TimeInterval = 60 * 60 * 6
    private let songLifetime: TimeInterval = 60 * 30

    private static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    /// 榜单目录里偶尔出现的运营位，桌面端也会把它们排到后面
    private static let catalogPalette = [
        ["5B4B8A", "8E54E9"], ["2B5876", "4E4376"], ["1D976C", "117A65"],
        ["C33764", "1D2671"], ["F7971E", "FFD200"], ["396AFC", "2948FF"],
        ["E23E57", "88304E"], ["00B4DB", "0083B0"],
    ]

    // MARK: - 榜单目录

    func catalog(for platform: BoardPlatform,
                 force: Bool = false,
                 completion: @escaping (Result<[MusicBoard], Error>) -> Void) {
        guard platform != .apple else {
            completion(.success(MusicBoard.appleBoards))
            return
        }
        if !force,
           let hit = catalogCache[platform],
           Date().timeIntervalSince(hit.date) < catalogLifetime,
           !hit.boards.isEmpty {
            completion(.success(hit.boards))
            return
        }

        let url: String
        let referer: String
        switch platform {
        case .kg:
            url = "https://m.kugou.com/rank/list&json=true"
            referer = "https://m.kugou.com/"
        case .tx:
            url = "https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg?format=json&inCharset=utf8&outCharset=utf-8"
            referer = "https://y.qq.com/"
        case .wy:
            url = "https://music.163.com/api/toplist"
            referer = "https://music.163.com/"
        case .apple:
            completion(.success(MusicBoard.appleBoards))
            return
        }

        fetchJSON(url, referer: referer) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let object):
                let boards = Self.parseCatalog(object, platform: platform)
                guard !boards.isEmpty else {
                    completion(.failure(BoardError.badResponse))
                    return
                }
                self.catalogCache[platform] = (boards, Date())
                completion(.success(boards))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func parseCatalog(_ object: Any, platform: BoardPlatform) -> [MusicBoard] {
        var items: [[String: Any]] = []
        if let root = object as? [String: Any] {
            switch platform {
            case .kg:
                if let rank = root["rank"] as? [String: Any],
                   let list = rank["list"] as? [[String: Any]] {
                    items = list
                }
            case .tx:
                if let data = root["data"] as? [String: Any],
                   let list = data["topList"] as? [[String: Any]] {
                    items = list
                }
            case .wy:
                items = root["list"] as? [[String: Any]] ?? []
            case .apple:
                items = []
            }
        }

        return items.enumerated().compactMap { index, item in
            let palette = catalogPalette[index % catalogPalette.count]
            switch platform {
            case .kg:
                let rankId = stringValue(item["rankid"])
                let name = stringValue(item["rankname"])
                guard !rankId.isEmpty, !name.isEmpty else { return nil }
                let cover = stringValue(item["imgurl"])
                    .replacingOccurrences(of: "{size}", with: "240")
                let freq = stringValue(item["update_frequency"])
                return MusicBoard(id: "kg_\(rankId)", platform: .kg,
                                  title: name,
                                  subtitle: freq.isEmpty ? "酷狗音乐榜单" : "更新：\(freq)",
                                  coverURL: https(cover),
                                  colors: palette,
                                  endpoint: .kugou(rankId: rankId))
            case .tx:
                let topId = stringValue(item["id"])
                let name = stringValue(item["topTitle"]).isEmpty
                    ? stringValue(item["title"])
                    : stringValue(item["topTitle"])
                guard !topId.isEmpty, !name.isEmpty else { return nil }
                return MusicBoard(id: "tx_\(topId)", platform: .tx,
                                  title: name,
                                  subtitle: "QQ 音乐榜单",
                                  coverURL: https(stringValue(item["picUrl"])),
                                  colors: palette,
                                  endpoint: .qq(topId: topId))
            case .wy:
                let playlistId = stringValue(item["id"])
                let name = stringValue(item["name"])
                guard !playlistId.isEmpty, !name.isEmpty else { return nil }
                let cover = stringValue(item["coverImgUrl"])
                let freq = stringValue(item["updateFrequency"])
                return MusicBoard(id: "wy_\(playlistId)", platform: .wy,
                                  title: name,
                                  subtitle: freq.isEmpty ? "网易云音乐榜单" : freq,
                                  coverURL: https(cover),
                                  colors: palette,
                                  endpoint: .netease(playlistId: playlistId))
            case .apple:
                return nil
            }
        }
    }

    // MARK: - 榜单曲目

    func songs(for board: MusicBoard,
               force: Bool = false,
               completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        if !force,
           let hit = songCache[board.id],
           Date().timeIntervalSince(hit.date) < songLifetime,
           !hit.songs.isEmpty {
            completion(.success(hit.songs))
            return
        }

        let finish: (Result<[MusicInfo], Error>) -> Void = { [weak self] result in
            if case .success(let songs) = result, !songs.isEmpty {
                self?.songCache[board.id] = (songs, Date())
            }
            completion(result)
        }

        switch board.endpoint {
        case .apple(let storefront):
            fetchAppleChart(storefront: storefront, attempt: 0, completion: finish)
        case .kugou(let rankId):
            fetchKugouRank(rankId: rankId, page: 1, collected: [], completion: finish)
        case .qq(let topId):
            fetchQQTop(topId: topId, completion: finish)
        case .netease(let playlistId):
            fetchNeteaseTop(playlistId: playlistId, completion: finish)
        }
    }

    // MARK: - Apple

    private static let appleHosts = [
        "https://rss.applemarketingtools.com",
        "https://rss.marketingtools.apple.com",
    ]

    /// 两个域名指向同一份数据，实测会交替超时，请求时轮换
    private func fetchAppleChart(storefront: String,
                                 attempt: Int,
                                 completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let host = Self.appleHosts[attempt % Self.appleHosts.count]
        let url = "\(host)/api/v2/\(storefront)/music/most-played/50/songs.json"
        fetchJSON(url, referer: "https://rss.applemarketingtools.com/") { [weak self] result in
            switch result {
            case .success(let object):
                let songs = Self.parseAppleChart(object, storefront: storefront)
                if songs.isEmpty {
                    self?.retryApple(storefront: storefront, attempt: attempt, completion: completion)
                } else {
                    completion(.success(songs))
                }
            case .failure:
                self?.retryApple(storefront: storefront, attempt: attempt, completion: completion)
            }
        }
    }

    private func retryApple(storefront: String,
                            attempt: Int,
                            completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        guard attempt < 2 else {
            completion(.failure(BoardError.badResponse))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.fetchAppleChart(storefront: storefront, attempt: attempt + 1, completion: completion)
        }
    }

    /// RSS 结构：{ feed: { results: [ { id, name, artistName, artworkUrl100 } ] } }
    private static func parseAppleChart(_ object: Any, storefront: String) -> [MusicInfo] {
        guard let root = object as? [String: Any],
              let feed = root["feed"] as? [String: Any],
              let results = feed["results"] as? [[String: Any]] else {
            return []
        }
        return results.enumerated().compactMap { index, item in
            let name = stringValue(item["name"])
            guard !name.isEmpty else { return nil }
            let trackId = stringValue(item["id"]).isEmpty ? "\(storefront)-\(index)" : stringValue(item["id"])
            let artist = stringValue(item["artistName"])
            var raw = item
            raw["source"] = "itunes"
            raw["storefront"] = storefront
            return MusicInfo.make(id: "itunes_\(trackId)",
                                  name: name,
                                  singer: artist,
                                  source: "itunes",
                                  songId: trackId,
                                  picUrl: MusicInfo.hdArtwork(stringValue(item["artworkUrl100"])),
                                  raw: raw)
        }
    }

    // MARK: - 酷狗

    /// 酷狗接口一页 30 首，取两页凑够 60 首；再多意义不大，反而拖慢进入榜单的速度
    private func fetchKugouRank(rankId: String,
                                page: Int,
                                collected: [MusicInfo],
                                completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let url = "https://m.kugou.com/rank/info/?rankid=\(rankId)&page=\(page)&json=true"
        fetchJSON(url, referer: "https://m.kugou.com/") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let object):
                let songs = Self.parseKugouSongs(object)
                let merged = collected + songs.filter { song in
                    !collected.contains { $0.id == song.id }
                }
                if merged.isEmpty {
                    completion(.failure(BoardError.empty))
                } else if page < 2, songs.count >= 20 {
                    self.fetchKugouRank(rankId: rankId, page: page + 1,
                                        collected: merged, completion: completion)
                } else {
                    completion(.success(merged))
                }
            case .failure(let error):
                if collected.isEmpty {
                    completion(.failure(error))
                } else {
                    completion(.success(collected))
                }
            }
        }
    }

    private static func parseKugouSongs(_ object: Any) -> [MusicInfo] {
        guard let root = object as? [String: Any],
              let songs = root["songs"] as? [String: Any],
              let list = songs["list"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            let hash = stringValue(item["hash"])
            guard !hash.isEmpty else { return nil }

            let filename = stringValue(item["filename"])
            let rawName = stringValue(item["songname"])
            let remark = stringValue(item["remark"])
            let name = !rawName.isEmpty ? rawName : splitFilename(filename).name
            let singer = authorName(item) ?? splitFilename(filename).singer
            let albumId = stringValue(item["album_id"])
            let duration = numberValue(item["duration"])
            let interval = duration > 0 ? MusicInfo.formatInterval(duration) : nil

            var raw = item
            raw["songmid"] = hash
            raw["hash"] = hash
            raw["songId"] = hash
            raw["name"] = name
            raw["singer"] = singer
            raw["interval"] = interval ?? ""
            raw["source"] = "kg"
            raw["albumName"] = remark.isEmpty ? filename : remark
            if !albumId.isEmpty {
                raw["albumId"] = albumId
                raw["album_id"] = albumId
            }
            // 部分音源脚本会按音质读取 `_types` 里的 hash
            var types: [String: Any] = [:]
            types["128k"] = ["hash": hash, "size": item["filesize"] ?? 0] as [String: Any]
            types["320k"] = ["hash": stringValue(item["320hash"]).isEmpty ? hash : stringValue(item["320hash"]),
                             "size": item["320filesize"] ?? 0] as [String: Any]
            types["flac"] = ["hash": stringValue(item["sqhash"]).isEmpty ? hash : stringValue(item["sqhash"]),
                             "size": item["sqfilesize"] ?? 0] as [String: Any]
            raw["_types"] = types

            let cover = albumId.isEmpty ? nil : "https://imge.kugou.com/stdmusic/240/\(albumId).jpg"
            return MusicInfo.make(id: "kg_\(hash)",
                                  name: name,
                                  singer: singer,
                                  source: "kg",
                                  interval: interval,
                                  songId: hash,
                                  albumName: remark.isEmpty ? filename : remark,
                                  picUrl: cover,
                                  raw: raw)
        }
    }

    private static func authorName(_ item: [String: Any]) -> String? {
        guard let authors = item["authors"] as? [[String: Any]] else { return nil }
        let names = authors.compactMap { stringValue($0["author_name"]) }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: "/")
    }

    /// 酷狗大部分曲目只给 `filename = "歌手 - 歌名"`，需要自己拆
    private static func splitFilename(_ filename: String) -> (singer: String, name: String) {
        let parts = filename.components(separatedBy: " - ")
        guard parts.count >= 2 else { return ("", filename) }
        let singer = parts.dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        let name = parts.last?.trimmingCharacters(in: .whitespaces) ?? filename
        return (singer, name)
    }

    // MARK: - QQ 音乐

    private func fetchQQTop(topId: String,
                            completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?topid=\(topId)&format=json&page=detail&tpl=3&type=top&inCharset=utf8&outCharset=utf-8"
        fetchJSON(url, referer: "https://y.qq.com/") { result in
            switch result {
            case .success(let object):
                let songs = Self.parseQQSongs(object)
                completion(songs.isEmpty ? .failure(BoardError.empty) : .success(songs))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func parseQQSongs(_ object: Any) -> [MusicInfo] {
        guard let root = object as? [String: Any],
              let list = root["songlist"] as? [[String: Any]] else {
            return []
        }
        // 部分榜单（如「巅峰榜·热歌」）一次返回 300 首，截到 100 首足够，避免详情页过重
        return list.prefix(100).compactMap { entry in
            guard let data = entry["data"] as? [String: Any] else { return nil }
            let songmid = stringValue(data["songmid"])
            let name = stringValue(data["songname"])
            guard !songmid.isEmpty, !name.isEmpty else { return nil }

            let singers = (data["singer"] as? [[String: Any]] ?? [])
                .compactMap { stringValue($0["name"]) }
                .filter { !$0.isEmpty }
            let albummid = stringValue(data["albummid"])
            let albumname = stringValue(data["albumname"])
            let seconds = numberValue(data["interval"])
            let interval = seconds > 0 ? MusicInfo.formatInterval(seconds) : nil

            var raw = data
            raw["songmid"] = songmid
            raw["songId"] = stringValue(data["songid"]).isEmpty ? songmid : stringValue(data["songid"])
            raw["name"] = name
            raw["singer"] = singers.joined(separator: "/")
            raw["interval"] = interval ?? ""
            raw["source"] = "tx"

            let cover = albummid.isEmpty
                ? nil
                : "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(albummid).jpg"
            return MusicInfo.make(id: "tx_\(songmid)",
                                  name: name,
                                  singer: singers.joined(separator: "/"),
                                  source: "tx",
                                  interval: interval,
                                  songId: songmid,
                                  albumName: albumname,
                                  picUrl: cover,
                                  raw: raw)
        }
    }

    // MARK: - 网易云音乐

    private func fetchNeteaseTop(playlistId: String,
                                 completion: @escaping (Result<[MusicInfo], Error>) -> Void) {
        let url = "https://music.163.com/api/playlist/detail?id=\(playlistId)"
        fetchJSON(url, referer: "https://music.163.com/") { result in
            switch result {
            case .success(let object):
                let songs = Self.parseNeteaseSongs(object)
                completion(songs.isEmpty ? .failure(BoardError.empty) : .success(songs))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func parseNeteaseSongs(_ object: Any) -> [MusicInfo] {
        guard let root = object as? [String: Any],
              let result = root["result"] as? [String: Any],
              let tracks = result["tracks"] as? [[String: Any]] else {
            return []
        }
        return tracks.compactMap { item in
            let songId = stringValue(item["id"])
            let name = stringValue(item["name"])
            guard !songId.isEmpty, !name.isEmpty else { return nil }

            // 新旧接口字段不同：旧版 artists / album，新版 ar / al
            let singerList = (item["artists"] as? [[String: Any]])
                ?? (item["ar"] as? [[String: Any]])
                ?? []
            let singers = singerList.compactMap { stringValue($0["name"]) }.filter { !$0.isEmpty }
            let album = (item["album"] as? [String: Any]) ?? (item["al"] as? [String: Any]) ?? [:]
            let albumName = stringValue(album["name"])
            let picUrl = https(stringValue(album["picUrl"]))
            let millis = numberValue(item["duration"])
            let interval = millis > 0 ? MusicInfo.formatInterval(millis / 1000) : nil

            var raw = item
            raw["songmid"] = songId
            raw["songId"] = songId
            raw["name"] = name
            raw["singer"] = singers.joined(separator: "/")
            raw["interval"] = interval ?? ""
            raw["albumName"] = albumName
            raw["source"] = "wy"
            if let pic = picUrl { raw["picUrl"] = pic }

            return MusicInfo.make(id: "wy_\(songId)",
                                  name: name,
                                  singer: singers.joined(separator: "/"),
                                  source: "wy",
                                  interval: interval,
                                  songId: songId,
                                  albumName: albumName,
                                  picUrl: picUrl,
                                  raw: raw)
        }
    }

    // MARK: - 通用请求

    /// 各平台接口都要求带手机 UA；QQ 返回带 BOM，需要先剥掉
    private func fetchJSON(_ urlString: String,
                           referer: String,
                           attempt: Int = 0,
                           completion: @escaping (Result<Any, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(BoardError.badResponse))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let retry: () -> Void = {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    self?.fetchJSON(urlString, referer: referer, attempt: attempt + 1, completion: completion)
                }
            }
            if error != nil {
                if attempt < 1 { retry() } else { DispatchQueue.main.async { completion(.failure(BoardError.badResponse)) } }
                return
            }
            guard var payload = data, !payload.isEmpty else {
                if attempt < 1 { retry() } else { DispatchQueue.main.async { completion(.failure(BoardError.badResponse)) } }
                return
            }
            if payload.starts(with: Data([0xEF, 0xBB, 0xBF])) {
                payload = payload.dropFirst(3)
            }
            guard let object = try? JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed]) else {
                if attempt < 1 { retry() } else { DispatchQueue.main.async { completion(.failure(BoardError.badResponse)) } }
                return
            }
            DispatchQueue.main.async { completion(.success(object)) }
        }.resume()
    }

    // MARK: - 字段兼容

    /// 同一字段在不同平台/版本里可能是字符串也可能是数字
    private static func stringValue(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func numberValue(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) ?? 0 }
        return 0
    }

    private static func https(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        if trimmed.hasPrefix("http://") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        return trimmed
    }
}
