import SwiftUI
import UIKit

enum AppTab: Int {
    case discover
    case library
    case settings
}

struct RootView: View {
    @ObservedObject private var player = PlayerService.shared
    @State private var tab: AppTab = .discover
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                DiscoverView()
                    .tabItem { Label("发现", systemImage: "magnifyingglass") }
                    .tag(AppTab.discover)
                LibraryView()
                    .tabItem { Label("我的", systemImage: "music.note.list") }
                    .tag(AppTab.library)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }

            if player.current != nil {
                MiniPlayerView(showPlayer: $showPlayer)
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottomSafeArea + 54)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(LibraryStore.shared)
        .environmentObject(SourceManager.shared)
        .environmentObject(SettingsStore.shared)
        .animation(.easeInOut(duration: 0.22), value: player.current != nil)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(LibraryStore.shared)
        }
    }

    private var bottomSafeArea: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first?.safeAreaInsets.bottom ?? 0
    }
}
