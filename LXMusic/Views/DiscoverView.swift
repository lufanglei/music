import SwiftUI

struct DiscoverView: View {
    @ObservedObject private var sources = SourceManager.shared
    @State private var keyword = ""
    @State private var results: [MusicInfo] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var hasSearched = false
    @State private var page = 0
    @State private var hasMore = true

    var body: some View {
        NavigationStack {
            List {
                if !hasSearched {
                    Section("热门搜索") { hotKeywordsGrid }
                    Section("当前音源") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(sources.isReady ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(sources.status)
                                    .font(.subheadline)
                            }
                            Text("搜索结果由搜索接口提供，播放链接由「设置 → 自定义音源」里的脚本返回，与洛雪的分工一致。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    if let message = message {
                        Section {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Section {
                        if !results.isEmpty {
                            Button { PlayerService.shared.playAll(results) } label: {
                                Label("播放全部", systemImage: "play.fill")
                            }
                        }
                        ForEach(results) { music in
                            SongRow(music: music) {
                                PlayerService.shared.play(music, in: results)
                            }
                        }
                        if !results.isEmpty && hasMore {
                            Button {
                                page += 1
                                performSearch(append: true)
                            } label: {
                                HStack {
                                    Text("加载更多")
                                    if isLoading { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(isLoading)
                        }
                    } header: {
                        Text("搜索结果 · \(results.count) 首")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("发现音乐")
            .searchable(text: $keyword, prompt: "搜索歌曲、歌手、专辑")
            .onSubmit(of: .search) {
                page = 0
                performSearch()
            }
            .overlay {
                if isLoading && results.isEmpty {
                    ProgressView().scaleEffect(1.2)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(sources.isReady ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(sources.isReady ? "音源就绪" : "音源未就绪")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var hotKeywordsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
            ForEach(SearchService.hotKeywords, id: \.self) { word in
                Button {
                    keyword = word
                    page = 0
                    performSearch()
                } label: {
                    Text(word)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(UIColor.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func performSearch(append: Bool = false) {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        message = nil
        hasSearched = true
        SearchService.shared.search(keyword: text, page: page) { result in
            isLoading = false
            switch result {
            case .success(let list):
                if append {
                    let existing = Set(results.map { $0.id })
                    results.append(contentsOf: list.filter { !existing.contains($0.id) })
                } else {
                    results = list
                    hasMore = true
                }
                // 单页满 50 条才认为还有下一页
                hasMore = hasMore && list.count >= 50
                if results.isEmpty {
                    message = "没有找到相关歌曲。中文歌名/歌手会自动走中港台曲库，如果仍为空可以换个关键词，或在设置里切换搜索接口。"
                }
            case .failure(let error):
                message = "搜索失败：\(error.localizedDescription)"
            }
        }
    }
}
