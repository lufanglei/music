import Foundation

/// 「我的列表」，对应洛雪桌面版的列表机制
struct Playlist: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var musics: [MusicInfo]
    var createdAt: TimeInterval

    static func new(name: String) -> Playlist {
        Playlist(id: UUID().uuidString,
                 name: name,
                 musics: [],
                 createdAt: Date().timeIntervalSince1970)
    }
}

/// 音源脚本在 inited 事件中声明的能力
struct SourceCapability: Codable, Hashable {
    var name: String
    var actions: [String]
    var qualitys: [String]
}

/// 一条自定义音源脚本
struct ScriptSource: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var description: String
    var version: String
    var author: String
    var homepage: String
    var script: String
    var addedAt: TimeInterval

    static func from(script: String, fallbackName: String = "未命名音源") -> ScriptSource {
        let info = ScriptMetadata.parse(script)
        return ScriptSource(id: UUID().uuidString,
                            name: info["name"] ?? fallbackName,
                            description: info["description"] ?? "",
                            version: info["version"] ?? "",
                            author: info["author"] ?? "",
                            homepage: info["homepage"] ?? "",
                            script: script,
                            addedAt: Date().timeIntervalSince1970)
    }
}

/// 解析脚本头部的 `@name` 等元数据，规则与洛雪一致
enum ScriptMetadata {
    static func parse(_ script: String) -> [String: String] {
        var result: [String: String] = [:]
        let head = String(script.prefix(2000))
        let keys = ["name", "description", "version", "author", "homepage"]
        for key in keys {
            let pattern = "@" + key + "\\s+([^\\r\\n*]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(head.startIndex..<head.endIndex, in: head)
            if let match = regex.firstMatch(in: head, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: head) {
                let value = String(head[valueRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*/ "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { result[key] = value }
            }
        }
        return result
    }
}

enum PlayMode: String, Codable, CaseIterable {
    case listLoop
    case singleLoop
    case shuffle

    var title: String {
        switch self {
        case .listLoop: return "列表循环"
        case .singleLoop: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var symbol: String {
        switch self {
        case .listLoop: return "repeat"
        case .singleLoop: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

struct LyricLine: Identifiable, Hashable {
    var id: Int
    var time: Double
    var text: String
}

struct LyricResult {
    var lyric: String = ""
    var tlyric: String?
    var rlyric: String?
    var lxlyric: String?
}
