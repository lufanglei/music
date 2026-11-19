import Foundation
import AVFoundation

/// 从「文件」App / Finder 文件共享导入本地音频，读取内嵌元数据后复制到 App 沙盒。
enum LocalMusicImporter {
    private static let supported = Set(["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf", "alac", "mp4"])

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalMusic", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func importFile(from url: URL, completion: @escaping (Result<MusicInfo, Error>) -> Void) {
        let ext = url.pathExtension.lowercased()
        guard supported.contains(ext) else {
            completion(.failure(LXError.script("不支持的音频格式: .\(ext)")))
            return
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let uuid = UUID().uuidString
        let destination = directory.appendingPathComponent(uuid + "." + ext)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            completion(.failure(error))
            return
        }

        let asset = AVURLAsset(url: destination)
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?

        for item in asset.commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case "title": title = item.stringValue
            case "artist": artist = item.stringValue
            case "albumName": album = item.stringValue
            case "artwork":
                if let data = item.value as? Data {
                    artwork = data
                } else if let dict = item.value as? [String: Any],
                          let data = dict["data"] as? Data {
                    artwork = data
                }
            default: break
            }
        }

        var picPath: String?
        if let artwork = artwork {
            let picURL = directory.appendingPathComponent(uuid + ".jpg")
            try? artwork.write(to: picURL)
            picPath = picURL.path
        }

        let seconds = CMTimeGetSeconds(asset.duration)
        let name = title ?? url.deletingPathExtension().lastPathComponent
        var raw: [String: Any] = [
            "name": name,
            "singer": artist ?? "",
            "filePath": destination.path,
            "songId": uuid,
        ]
        if let picPath = picPath { raw["picUrl"] = picPath }

        var meta = MusicMeta()
        meta.songId = uuid
        meta.albumName = album ?? ""
        meta.filePath = destination.path
        meta.ext = ext
        meta.picUrl = picPath

        let music = MusicInfo(id: "local_" + uuid,
                              name: name,
                              singer: artist ?? "未知歌手",
                              source: "local",
                              interval: seconds.isFinite && seconds > 0
                                        ? MusicInfo.formatInterval(seconds) : nil,
                              meta: meta,
                              rawJSON: Self.jsonString(raw))
        completion(.success(music))
    }

    /// 扫描通过 Finder 文件共享（UIFileSharingEnabled）直接放进 Documents 的音频
    static func scanDocuments(completion: @escaping ([MusicInfo]) -> Void) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let audios = files.filter { supported.contains($0.pathExtension.lowercased()) }
        var result: [MusicInfo] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for file in audios {
            group.enter()
            importFile(from: file) { value in
                if case .success(let music) = value {
                    lock.lock()
                    result.append(music)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(result) }
    }

    private static func jsonString(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
