// HGHub iOS v1 — Detail: full episode list in one response (map §5.3).
// All episodes are playable; there is no lock / paywall UI.

import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var api: HGHubAPI
    @EnvironmentObject private var history: HistoryStore

    var videoId: Int

    @State private var detail: Detail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEpisode: Episode?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            CoverImage(urlString: detail.cover)
                                .frame(width: 120, height: 160)
                                .cornerRadius(8)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(detail.title)
                                    .font(.headline)
                                if detail.score > 0 {
                                    Text("评分 \(detail.score, specifier: "%.1f")")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                                Text("\(detail.episode_count)集 · \(detail.is_finished ? "已完结" : "连载中")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("热度 \(detail.counts.hot) · 评论 \(detail.counts.comment)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let author = detail.author {
                                    Text("作者：\(author.name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)

                        if let resume = history.entry(for: videoId) {
                            Button {
                                if let ep = detail.episodes.first(where: { $0.ep_num == resume.ep }) {
                                    selectedEpisode = ep
                                }
                            } label: {
                                Label("继续观看 第 \(resume.ep) 集", systemImage: "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                        }

                        if !detail.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(detail.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color(uiColor: .secondarySystemBackground))
                                            .cornerRadius(12)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        if !detail.description.isEmpty {
                            Text(detail.description)
                                .font(.subheadline)
                                .padding(.horizontal)
                        }

                        Text("分集（共 \(detail.episodes.count) 集）")
                            .font(.headline)
                            .padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
                            ForEach(detail.episodes) { episode in
                                Button("\(episode.ep_num)") {
                                    selectedEpisode = episode
                                }
                                .buttonStyle(.bordered)
                                .tint(history.entry(for: videoId)?.ep == episode.ep_num ? .accentColor : .secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            } else if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
            }
        }
        .navigationTitle(detail?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $selectedEpisode) { episode in
            if let detail {
                PlayerView(detail: detail, startEpisode: episode)
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await api.video(id: videoId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
