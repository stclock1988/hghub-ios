// HGHub iOS v1 — Search. The query param MUST be `q` (map §5.2).

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var api: HGHubAPI

    @State private var query = ""
    @State private var cards: [VideoCard] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("热门搜索")
                    .font(.headline)
                    .padding(.horizontal)
                FlexibleTagCloud(tags: hghubHotTags) { tag in
                    query = tag
                    Task { await run(page: 1) }
                }
                .padding(.horizontal)

                if searched {
                    VideoGrid(cards: cards)
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if let errorMessage {
                        ErrorStateView(message: errorMessage) { Task { await run(page: 1) } }
                    } else if cards.isEmpty {
                        Text("没有找到相关内容")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if hasMore {
                        Button("加载更多") { Task { await run(page: page + 1) } }
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "输入剧名搜索")
        .onSubmit(of: .search) { Task { await run(page: 1) } }
    }

    private func run(page targetPage: Int) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        searched = true
        defer { isLoading = false }
        do {
            let result = try await api.search(query: trimmed, page: targetPage, size: 20)
            if targetPage == 1 {
                cards = result.items
            } else {
                let known = Set(cards.map(\.id))
                cards += result.items.filter { !known.contains($0.id) }
            }
            page = targetPage
            hasMore = result.pagination.page < result.pagination.pages
        } catch {
            if targetPage == 1 { errorMessage = error.localizedDescription }
        }
    }
}

/// Simple flow layout for the hot-tag chips.
struct FlexibleTagCloud: View {
    var tags: [String]
    var onTap: (String) -> Void

    var body: some View {
        // A plain wrapping layout via LazyVGrid with adaptive columns
        // is good enough for 12 short tags.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button(tag) { onTap(tag) }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(16)
            }
        }
    }
}
