// HGHub iOS v1 — Category: the four fixed categories (map §5.2.1).

import SwiftUI

struct CategoryView: View {
    @EnvironmentObject private var api: HGHubAPI

    @State private var category: HGHubCategory = .aiDuanju
    @State private var cards: [VideoCard] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("分类", selection: $category) {
                    ForEach(HGHubCategory.allCases) { cate in
                        Text(cate.displayName).tag(cate)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                VideoGrid(cards: cards)
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
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
        .navigationTitle("分类")
        .task(id: category) { await load(page: 1) }
    }

    private func load(page targetPage: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let paged = try await api.category(category, page: targetPage, size: 20)
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
