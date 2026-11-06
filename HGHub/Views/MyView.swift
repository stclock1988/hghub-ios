// HGHub iOS v1 — My: local history, line settings, About.
// No account UI in v1 (guest only).

import SwiftUI

struct MyView: View {
    @EnvironmentObject private var edge: EdgeClient
    @EnvironmentObject private var history: HistoryStore

    @State private var showClearHistory = false

    private var buildLabel: String {
        Bundle.main.infoDictionary?["BuildLabel"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section("继续观看") {
                if history.entries.isEmpty {
                    Text("还没有观看记录")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(history.entries) { entry in
                        NavigationLink(destination: DetailView(videoId: entry.videoId)) {
                            HStack(spacing: 12) {
                                CoverImage(urlString: entry.cover)
                                    .frame(width: 48, height: 64)
                                    .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .lineLimit(1)
                                    Text("第 \(entry.ep) 集 · 已看到 \(formatTime(entry.seconds)) / \(formatTime(entry.duration))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                history.remove(videoId: entry.videoId)
                            }
                        }
                    }
                }
            }

            Section("设置") {
                Picker("线路", selection: $edge.base) {
                    ForEach(EdgeClient.lines, id: \.self) { line in
                        Text(line).tag(line)
                    }
                }
                .onChange(of: edge.base) { newBase in
                    edge.setBase(newBase)
                }
                Button("清理封面缓存") {
                    CoverDecryptor.shared.clearCache()
                }
                Button("清空观看记录", role: .destructive) {
                    showClearHistory = true
                }
                .alert("清空观看记录？", isPresented: $showClearHistory) {
                    Button("清空", role: .destructive) { history.clear() }
                    Button("取消", role: .cancel) {}
                }
            }

            Section("关于") {
                Text("HGHub iOS 是 Minireel/HGhub 的第三方 iOS 移植版，仅供个人学习与自用。内容来自第三方站点，本应用不提供、不存储、不分发任何音视频内容。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("许可证：PolyForm Noncommercial 1.0.0（仅限非商业用途，禁止出售、广告、会员与付费点播）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Required Notice: Copyright (c) 2026 HGhub contributors (https://github.com/Minireel/HGhub)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("游客模式：v1 不做登录、收藏、评论与吃瓜帖子，只做浏览与播放。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("BuildLabel \(buildLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("我的")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
