import SwiftUI

@main
struct LXMusicApp: App {
    init() {
        // 启动时激活音频会话，保证首次播放与后台/锁屏控制可用
        AudioSessionManager.shared.activate()
        // 载入已保存的音源并初始化脚本上下文
        SourceManager.shared.load()
        LibraryStore.shared.load()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
