import Foundation

/// 音质，对应 LX Music 的 `LX.Music.MusicQualityType`
struct MusicQuality: Codable, Hashable, Identifiable {
    var type: String
    var size: String?
    var id: String { type }
}

/// 歌曲附加信息，对应 `LX.Music.MusicInfoMetaBase`
struct MusicMeta: Codable, Hashable {
    var songId: String = ""
    var albumName: String = ""
    var picUrl: String?
    var filePath: String?
    var ext: String?
    var qualitys: [MusicQuality] = []

    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "songId": songId,
            "albumName": albumName,
        ]
        if let picUrl = picUrl { dict["picUrl"] = picUrl }
        if let filePath = filePath { dict["filePath"] = filePath }
        if let ext = ext { dict["ext"] = ext }
        dict["qualitys"] = qualitys.map { ["type": $0.type, "size": $0.size ?? ""] }
        return dict
    }
}

/// 与桌面版 `LX.Music.MusicInfo` 对齐的歌曲模型。
///
/// 注意 rawJSON：洛雪的自定义源脚本收到的 `info.musicInfo` 是桌面版内部完整对象，
/// 里面带有 songmid / hash / strMediaMid 等各平台专有字段。为了让现成的音源脚本
/// 在 iOS 上也能正常工作，这里把搜索结果的原始 JSON 原样保留并透传给脚本。
struct MusicInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var singer: String
    var source: String
    var interval: String?
    var meta: MusicMeta
    var rawJSON: String?

    var displaySinger: String { singer.isEmpty ? "未知歌手" : singer }
    var displayName: String { name.isEmpty ? "未知歌曲" : name }

    /// 转换成传给音源脚本的 `musicInfo` 对象
    func scriptDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let rawJSON = rawJSON,
           let data = rawJSON.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            dict = parsed
        }
        dict["id"] = id
        dict["name"] = name
        dict["singer"] = singer
        dict["source"] = source
        dict["interval"] = interval ?? ""
        dict["meta"] = meta.asDictionary()
        // 常见别名，方便脚本直接取用
        if dict["songId"] == nil { dict["songId"] = meta.songId }
        if dict["picUrl"] == nil, let pic = meta.picUrl { dict["picUrl"] = pic }
        if dict["albumName"] == nil { dict["albumName"] = meta.albumName }
        return dict
    }

    static func make(id: String,
                     name: String,
                     singer: String,
                     source: String,
                     interval: String? = nil,
                     songId: String? = nil,
                     albumName: String = "",
                     picUrl: String? = nil,
                     raw: [String: Any]? = nil) -> MusicInfo {
        var meta = MusicMeta()
        meta.songId = songId ?? id
        meta.albumName = albumName
        meta.picUrl = picUrl
        var rawJSON: String?
        if let raw = raw, let data = try? JSONSerialization.data(withJSONObject: raw, options: []) {
            rawJSON = String(data: data, encoding: .utf8)
        }
        return MusicInfo(id: id,
                         name: name,
                         singer: singer,
                         source: source,
                         interval: interval,
                         meta: meta,
                         rawJSON: rawJSON)
    }

    static func formatInterval(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
