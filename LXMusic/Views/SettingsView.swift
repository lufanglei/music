import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var sources = SourceManager.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var showURLImport = false
    @State private var showTextImport = false
    @State private var showFileImport = false
    @State private var fileImportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(sources.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    if !sources.sources.isEmpty {
                        Picker("当前音源", selection: Binding(
                            get: { sources.activeSourceID ?? "" },
                            set: { sources.activate(id: $0) }
                        )) {
                            ForEach(sources.sources) { source in
                                Text(source.name).tag(source.id)
                            }
                        }
                    }
                    ForEach(sources.sources) { source in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(source.name).font(.subheadline)
                                if source.id == sources.activeSourceID {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            if !source.description.isEmpty {
                                Text(source.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            let subtitle = [source.version, source.author]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        offsets.compactMap { sources.sources.indices.contains($0) ? sources.sources[$0].id : nil }
                            .forEach { sources.remove(id: $0) }
                    }
                } header: {
                    Text("自定义音源")
                } footer: {
                    Text("与洛雪一致：App 本身不提供音乐数据，musicUrl / lyric / pic 全部由导入的 JS 音源脚本返回。现成的 LX Music 音源脚本可以直接导入。")
                }

                Section {
                    Button("从 URL 导入脚本") { showURLImport = true }
                    Button("粘贴脚本内容") { showTextImport = true }
                    Button("从「文件」App 选择 .js") { showFileImport = true }
                    Button("安装 / 重置内置示例源") { sources.installDemoSource() }
                    Button("重新加载当前音源") { sources.reload() }
                } header: {
                    Text("导入与管理")
                }

                if !sources.capabilities.isEmpty {
                    Section("音源能力（inited 声明）") {
                        ForEach(sources.capabilities.keys.sorted(), id: \.self) { key in
                            if let cap = sources.capabilities[key] {
                                SourceCapabilityRow(key: key, capability: cap)
                            }
                        }
                    }
                }

                if let alert = sources.updateAlert {
                    Section("音源更新提示") {
                        Text(alert.log).font(.caption)
                        if let url = alert.url, let link = URL(string: url) {
                            Link("前往更新", destination: link)
                        }
                    }
                }

                Section {
                    Picker("搜索接口", selection: $settings.searchMode) {
                        ForEach(SearchProviderMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if settings.searchMode == .custom {
                        TextField("https://your.api/search?keyword={keyword}&page={page}",
                                  text: $settings.customSearchURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 13, design: .monospaced))
                    }
                    Text("内置 Apple 曲库返回官方 30 秒试听；自定义接口返回洛雪风格的歌曲数组，原始字段会原样透传给音源脚本。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("搜索来源")
                }

                Section {
                    Picker("默认音质", selection: $settings.preferredQuality) {
                        ForEach(["128k", "320k", "flac", "flac24bit"], id: \.self) { quality in
                            Text(quality).tag(quality)
                        }
                    }
                    Picker("lx.env 运行环境", selection: $settings.scriptEnv) {
                        Text("mobile（推荐，兼容移动版音源）").tag("mobile")
                        Text("desktop（兼容桌面版音源）").tag("desktop")
                    }
                    Button("应用 env 并重载音源") { sources.reload() }
                    Text("实际可用音质由音源脚本 inited 时声明的 qualitys 决定，App 会自动回退到脚本支持的最接近音质。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("播放")
                }

                Section {
                    NavigationLink("运行日志") { LogView() }
                } header: {
                    Text("调试")
                }

                Section {
                    LabeledContent("工程来源", value: "lx-music-desktop")
                    Text("本工程是参考洛雪音乐助手的自定义源协议开发的独立 iOS 客户端，仅用于技术学习与研究。请尊重版权、支持正版，勿用于商业用途。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showURLImport) { SourceURLImportView() }
            .sheet(isPresented: $showTextImport) { SourceTextImportView() }
            .fileImporter(isPresented: $showFileImport,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: false) { result in
                handleFileImport(result)
            }
            .alert("导入失败", isPresented: Binding(
                get: { fileImportError != nil },
                set: { if !$0 { fileImportError = nil } }
            )) {
                Button("好", role: .cancel) { fileImportError = nil }
            } message: {
                Text(fileImportError ?? "")
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let script = try? String(contentsOf: url, encoding: .utf8) else {
                fileImportError = "无法读取该文件，请确认是 UTF-8 编码的 .js 脚本"
                return
            }
            let source = sources.add(script: script)
            sources.activate(id: source.id)
        case .failure(let error):
            fileImportError = error.localizedDescription
        }
    }
}

private struct SourceCapabilityRow: View {
    let key: String
    let capability: SourceCapability

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(key) · \(capability.name)")
                .font(.subheadline)
            Text("actions: \(capability.actions.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("音质: \(capability.qualitys.isEmpty ? "不限" : capability.qualitys.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 导入

struct SourceURLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/source.js", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("音源脚本地址")
                } footer: {
                    Text("直接填写洛雪音源脚本的在线地址，App 会下载并导入。请只使用你信任的来源。")
                }
                if let errorText = errorText {
                    Section { Text(errorText).font(.caption).foregroundColor(.red) }
                }
                Section {
                    Button {
                        download()
                    } label: {
                        HStack {
                            Text("下载并导入")
                            if isLoading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isLoading || urlText.isEmpty)
                }
            }
            .navigationTitle("从 URL 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func download() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            errorText = "请输入合法的 http(s) 地址"
            return
        }
        isLoading = true
        errorText = nil
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorText = error.localizedDescription
                    return
                }
                guard let data = data, let script = String(data: data, encoding: .utf8),
                      script.contains("lx") else {
                    errorText = "下载内容不是有效的音源脚本"
                    return
                }
                let source = SourceManager.shared.add(script: script)
                SourceManager.shared.activate(id: source.id)
                dismiss()
            }
        }.resume()
    }
}

struct SourceTextImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var script = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $script)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 260)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("粘贴脚本内容")
                } footer: {
                    Text("脚本头部建议包含 @name / @description / @version 等元数据，格式与洛雪桌面版一致。")
                }
                if let errorText = errorText {
                    Section { Text(errorText).font(.caption).foregroundColor(.red) }
                }
                Section {
                    Button("导入并启用") { commit() }
                        .disabled(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("粘贴脚本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func commit() {
        let text = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("EVENT_NAMES"), text.contains("inited") else {
            errorText = "内容看起来不是洛雪自定义源脚本（缺少 EVENT_NAMES / inited）"
            return
        }
        let source = SourceManager.shared.add(script: text)
        SourceManager.shared.activate(id: source.id)
        dismiss()
    }
}

// MARK: - 日志

struct LogView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        List {
            if settings.logs.isEmpty {
                Text("暂无日志").font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(settings.logs.reversed(), id: \.self) { line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle("运行日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空") { settings.logs.removeAll() }
            }
        }
    }
}
