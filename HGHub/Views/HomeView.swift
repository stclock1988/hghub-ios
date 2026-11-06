// HGHub iOS v1 — Home: all-site feed (infinite scroll) + ranks.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: HGHubAPI

    @State private var cards: [VideoCard] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var rankKind = "hot"
    @State private var ranks: [RankItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rankSection
                Text("全部")
                    .font(.headline)
                    .padding(.horizontal)
                VideoGrid(cards: cards)
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load(page: 1) } }
                } else if hasMore {
                    Button("加载更多") { Task { await load(page: page + 1) } }
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("HGHub")
        .refreshable { await load(page: 1) }
        .task { await load(page: 1); await loadRanks() }
    }

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("榜单")
                    .font(.headline)
                Spacer()
                Picker("榜单", selection: $rankKind) {
                    Text("热门").tag("hot")
                    Text("推荐").tag("recommend")
                    Text("潜力").tag("potential")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ranks) { item in
                        NavigationLink(destination: DetailView(videoId: item.video_id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverImage(urlString: item.cover)
                                    .frame(width: 100, height: 133)
                                    .cornerRadius(8)
                                Text("\(item.rank). \(item.title)")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: rankKind) { await loadRanks() }
    }

    private func loadRanks() async {
        do {
            ranks = try await api.ranks(kind: rankKind).items
        } catch {
            ranks = []
        }
    }

    private func load(page targetPage: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let paged = try await api.feed(page: targetPage, size: 20)
            if targetPage == 1 {
                cards = paged.items
            } else {
                let known = Set(cards.map(\.id))
                cards += paged.items.filter { !known.contains($0.id) }
            }
            page = targetPage
            hasMore = paged.pagination.page < paged.pagination.pages
        } catch {
            if targetPage == 1 && cards.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}
