import Foundation

enum SearchProviderMode: String, Codable, CaseIterable {
    case itunes
    case custom

    var title: String {
        switch self {
        case .itunes: return "Apple 曲库（内置）"
        case .custom: return "自定义搜索接口"
        }
    }
}

/// 应用级设置
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var searchMode: SearchProviderMode {
        didSet { defaults.set(searchMode.rawValue, forKey: Keys.searchMode) }
    }
    @Published var customSearchURL: String {
        didSet { defaults.set(customSearchURL, forKey: Keys.customSearchURL) }
    }
    /// 洛雪脚本通过 lx.env 判断宿主，移动版脚本占多数，默认 mobile 以最大化兼容
    @Published var scriptEnv: String {
        didSet { defaults.set(scriptEnv, forKey: Keys.scriptEnv) }
    }
    @Published var preferredQuality: String {
        didSet { defaults.set(preferredQuality, forKey: Keys.preferredQuality) }
    }
    @Published var logs: [String] = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let searchMode = "lx.search.mode"
        static let customSearchURL = "lx.search.url"
        static let scriptEnv = "lx.script.env"
        static let preferredQuality = "lx.player.quality"
    }

    private init() {
        let rawMode = UserDefaults.standard.string(forKey: Keys.searchMode) ?? ""
        searchMode = SearchProviderMode(rawValue: rawMode) ?? .itunes
        customSearchURL = UserDefaults.standard.string(forKey: Keys.customSearchURL) ?? ""
        scriptEnv = UserDefaults.standard.string(forKey: Keys.scriptEnv) ?? "mobile"
        preferredQuality = UserDefaults.standard.string(forKey: Keys.preferredQuality) ?? "128k"
    }

    func log(_ message: String) {
        let line = "[\(Self.timeString())] \(message)"
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 300 { self.logs.removeFirst(self.logs.count - 300) }
            NSLog("LXMusic: %@", message)
        }
    }

    private static func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
