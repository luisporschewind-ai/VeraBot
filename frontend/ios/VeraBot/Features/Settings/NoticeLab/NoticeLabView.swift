import SwiftUI

struct NoticeLabView: View {
    private let sample = BotNotice(title: "已保存", tone: .success, avatar: .success)

    var body: some View {
        ThemedList {
            Section {
                BotNoticeCard(notice: sample)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Text("每条提示都有小 Bot。先在这里调整和比较，正式页面仍使用现有提示。")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    NoticeWorkbenchView()
                } label: { Label("自由试验", systemImage: "slider.horizontal.3") }
                NavigationLink {
                    NoticeInteractionLabView()
                } label: { Label("交互与连续状态", systemImage: "play.rectangle") }
            } header: { Text("提示组件") }

            Section {
                NavigationLink("全部场景") { NoticeScenarioListView() }
                ForEach(NoticeScenarioCatalog.groupTitles, id: \.self) { group in
                    NavigationLink {
                        NoticeScenarioListView(group: group)
                    } label: {
                        LabeledContent(group, value: "\(NoticeScenarioCatalog.all.filter { $0.group == group }.count)")
                    }
                }
            } header: { Text("现有场景 · \(NoticeScenarioCatalog.all.count) 项") }
              footer: { Text("清单记录原有表现，并提供建议文案、Bot 状态和呈现位置。成功操作中尚无提示的，也列为待试验反馈。") }

            Section {
                NavigationLink {
                    NoticeSourceIndexView()
                } label: { Label("提示与状态代码索引", systemImage: "list.bullet.rectangle") }
                Text("静态盘点范围：iOS 页面、状态模型、服务及本地 Package。运行时服务端文案归入各功能失败场景，不视为穷尽所有远端错误。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("盘点依据") }
        }
        .navigationTitle("提示组件实验室").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("notice.lab")
    }
}

private struct NoticeScenarioListView: View {
    var group: String? = nil
    @State private var search = ""
    private var items: [NoticeScenario] {
        NoticeScenarioCatalog.all.filter {
            (group == nil || $0.group == group) && (search.isEmpty || "\($0.group) \($0.title) \($0.message) \($0.current) \($0.avatar.title)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ThemedList {
            ForEach(items) { scenario in
                NavigationLink {
                    NoticeWorkbenchView(scenario: scenario)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scenario.title)
                        Text("\(scenario.proposed.title) · Bot \(scenario.avatar.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(group ?? "全部提示场景").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "场景、文案或 Bot 状态")
        .overlay {
            if items.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }
}

struct NoticeSourceRecord: Decodable, Identifiable {
    let file: String
    let line: Int
    let kinds: [String]
    let excerpt: String
    var id: String { "\(file):\(line)" }
}

private struct NoticeSourceIndex: Decodable {
    let scope: String
    let records: [NoticeSourceRecord]
}

private struct NoticeSourceIndexView: View {
    @State private var search = ""
    @State private var records: [NoticeSourceRecord] = []
    @State private var loadError: String?

    private var filtered: [NoticeSourceRecord] {
        records.filter { search.isEmpty || "\($0.file) \($0.excerpt) \($0.kinds.joined())".localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ThemedList {
            Section {
                Text("\(records.count) 处匹配 · \(Set(records.map(\.file)).count) 个文件")
                Text("用于复核遗漏和追溯当前实现；包含匹配到的状态声明、错误处理和反馈位置，匹配条目不等于独立场景。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let loadError { Text(loadError).foregroundStyle(.red) }
            }
            ForEach(filtered) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(record.file):\(record.line)").font(.caption.weight(.semibold))
                    Text(record.kinds.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                    Text(record.excerpt).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("提示与状态代码索引").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "文件、状态或提示文字")
        .task {
            do {
                guard let url = Bundle.main.url(forResource: "NoticeSourceIndex", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                records = try JSONDecoder().decode(NoticeSourceIndex.self, from: Data(contentsOf: url)).records
            } catch { loadError = "索引读取失败：\(error.localizedDescription)" }
        }
    }
}
