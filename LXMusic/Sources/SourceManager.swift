import Foundation

/// 自定义音源管理：导入、切换、持久化，以及把 App 的播放请求分发给脚本。
/// 与洛雪一致：同一时间只启用一个自定义源，脚本通过 inited 声明它支持的 source / 音质 / action。
final class SourceManager: ObservableObject {
    static let shared = SourceManager()

    @Published var sources: [ScriptSource] = []
    @Published var activeSourceID: String?
    @Published var capabilities: [String: SourceCapability] = [:]
    @Published var status: String = "未加载音源"
    @Published var isReady = false
    @Published var updateAlert: (log: String, url: String?)?

    private var engine: ScriptEngine?
    private var hasLoaded = false

    private struct Store: Codable {
        var sources: [ScriptSource]
        var activeID: String?
    }

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("lx-sources.json")
    }

    // MARK: - 载入 / 保存

    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let data = try? Data(contentsOf: storeURL),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            sources = store.sources
            activeSourceID = store.activeID
        } else {
            installDemoSource(activate: true, silent: true)
        }
        rebuildEngine()
    }

    private func save() {
        let store = Store(sources: sources, activeID: activeSourceID)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - 增删改

    @discardableResult
    func add(script: String) -> ScriptSource {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = ScriptSource.from(script: trimmed)
        sources.append(source)
        if activeSourceID == nil { activeSourceID = source.id }
        save()
        if activeSourceID == source.id { rebuildEngine() }
        SettingsStore.shared.log("已导入音源: \(source.name)")
        return source
    }

    func remove(id: String) {
        sources.removeAll { $0.id == id }
        if activeSourceID == id { activeSourceID = sources.first?.id }
        save()
        rebuildEngine()
    }

    func activate(id: String) {
        activeSourceID = id
        save()
        rebuildEngine()
    }

    func reload() {
        rebuildEngine()
    }

    /// 一键安装内置的合规示例源（Apple 官方 30 秒试听）
    func installDemoSource(activate: Bool = true, silent: Bool = false) {
        guard let url = Bundle.main.url(forResource: "DemoSource", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            status = "示例音源资源缺失"
            return
        }
        let demo = ScriptSource.from(script: script, fallbackName: "示例音源")
        sources.removeAll { $0.name == demo.name }
        sources.insert(demo, at: 0)
        if activate || activeSourceID == nil { activeSourceID = demo.id }
        save()
        if !silent { SettingsStore.shared.log("已安装示例音源: \(demo.name)") }
        if activeSourceID == demo.id { rebuildEngine() }
    }

    // MARK: - 引擎

    private func rebuildEngine() {
        engine = nil
        capabilities = [:]
        isReady = false

        guard let id = activeSourceID,
              let source = sources.first(where: { $0.id == id }) else {
            status = "未选择音源，请到「设置 → 音源管理」导入"
            return
        }

        status = "正在初始化 \(source.name)…"
        let engine = ScriptEngine(source: source, env: SettingsStore.shared.scriptEnv)
        engine.onLog = { message in SettingsStore.shared.log("[音源] \(message)") }
        engine.onUpdateAlert = { [weak self] data in
            self?.updateAlert = (data["log"] as? String ?? "音源有更新", data["updateUrl"] as? String)
        }
        engine.onReady = { [weak self] ok, caps, message in
            guard let self = self else { return }
            self.capabilities = caps
            self.isReady = ok
            let keys = caps.keys.sorted().joined(separator: " / ")
            self.status = ok ? "\(source.name) 已就绪 · \(keys)" : "\(source.name) 初始化失败 · \(message)"
            SettingsStore.shared.log("音源状态: \(self.status)")
        }
        self.engine = engine
        engine.start()
    }

    // MARK: - 取播放链接 / 歌词 / 封面

    func musicURL(for music: MusicInfo,
                  quality: String? = nil,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        // 本地文件直接播放，不需要脚本
        if let path = music.meta.filePath, FileManager.default.fileExists(atPath: path) {
            completion(.success(URL(fileURLWithPath: path)))
            return
        }

        // 自定义搜索接口若已直接给出播放链接，且当前没有可用音源，则直接使用
        guard let engine = engine, engine.isReady else {
            if let direct = Self.directURL(from: music) {
                completion(.success(direct))
            } else {
                completion(.failure(LXError.noSource))
            }
            return
        }

        let (key, resolvedQuality) = resolveSource(for: music, action: "musicUrl", quality: quality)
        let info: [String: Any] = [
            "type": resolvedQuality as Any? ?? NSNull(),
            "musicInfo": music.scriptDictionary(),
        ]
        SettingsStore.shared.log("请求 musicUrl: \(music.name) [\(key)/\(resolvedQuality ?? "默认")]")

        engine.perform(action: "musicUrl", sourceKey: key, info: info) { result in
            switch result {
            case .success(let value):
                guard let urlString = Self.extractURL(value),
                      let url = URL(string: urlString),
                      url.scheme != nil else {
                    // 音源没给出链接时，退回歌曲自带的试听链接
                    if let direct = Self.directURL(from: music) {
                        completion(.success(direct))
                    } else {
                        completion(.failure(LXError.invalidResponse))
                    }
                    return
                }
                completion(.success(url))
            case .failure(let error):
                SettingsStore.shared.log("musicUrl 失败: \(error.localizedDescription)")
                if let direct = Self.directURL(from: music) {
                    completion(.success(direct))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    func lyric(for music: MusicInfo, completion: @escaping (Result<LyricResult, Error>) -> Void) {
        guard let engine = engine, engine.isReady,
              supports(action: "lyric", for: music.source) else {
            completion(.success(LyricResult()))
            return
        }
        let (key, _) = resolveSource(for: music, action: "lyric", quality: nil)
        engine.perform(action: "lyric", sourceKey: key,
                       info: ["musicInfo": music.scriptDictionary()]) { result in
            switch result {
            case .success(let value):
                var lyric = LyricResult()
                if let dict = value as? [String: Any] {
                    lyric.lyric = dict["lyric"] as? String ?? dict["lryic"] as? String ?? ""
                    lyric.tlyric = dict["tlyric"] as? String ?? dict["tlryic"] as? String
                    lyric.rlyric = dict["rlyric"] as? String
                    lyric.lxlyric = dict["lxlyric"] as? String
                } else if let text = value as? String {
                    lyric.lyric = text
                }
                completion(.success(lyric))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func pic(for music: MusicInfo, completion: @escaping (Result<String, Error>) -> Void) {
        guard let engine = engine, engine.isReady,
              supports(action: "pic", for: music.source) else {
            completion(.failure(LXError.noSource))
            return
        }
        let (key, _) = resolveSource(for: music, action: "pic", quality: nil)
        engine.perform(action: "pic", sourceKey: key,
                       info: ["musicInfo": music.scriptDictionary()]) { result in
            switch result {
            case .success(let value):
                if let url = Self.extractString(value), !url.isEmpty {
                    completion(.success(url))
                } else {
                    completion(.failure(LXError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - 内部

    private func supports(action: String, for sourceKey: String) -> Bool {
        if let cap = capabilities[sourceKey], cap.actions.contains(action) { return true }
        return capabilities.values.contains { $0.actions.contains(action) }
    }

    private func resolveSource(for music: MusicInfo,
                               action: String,
                               quality: String?) -> (String, String?) {
        var key = music.source
        if capabilities[key]?.actions.contains(action) != true {
            if let fallback = capabilities.first(where: { $0.value.actions.contains(action) })?.key {
                key = fallback
            }
        }
        let available = capabilities[key]?.qualitys ?? []
        // 返回类型是 (String, String?)：音质可能为空（脚本未声明 qualitys 或本地音乐）。
        var resolved: String? = quality ?? SettingsStore.shared.preferredQuality
        if let current = resolved {
            if !available.contains(current) { resolved = available.first }
        } else {
            resolved = available.first
        }
        if key == "local" { resolved = nil }
        return (key, resolved)
    }

    private static func directURL(from music: MusicInfo) -> URL? {
        guard let json = music.rawJSON,
              let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in ["previewUrl", "musicUrl", "url", "playUrl", "songUrl"] {
            if let value = dict[key] as? String,
               let url = URL(string: value),
               url.scheme == "http" || url.scheme == "https" {
                return url
            }
        }
        return nil
    }

    private static func extractString(_ value: Any) -> String? {
        if let text = value as? String { return text }
        if let dict = value as? [String: Any] {
            for key in ["url", "pic", "picUrl", "musicUrl", "lyric", "text"] {
                if let text = dict[key] as? String { return text }
            }
        }
        return nil
    }

    private static func extractURL(_ value: Any) -> String? {
        guard let text = extractString(value) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return trimmed
        }
        return nil
    }
}
