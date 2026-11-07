// HGHub iOS — Community: gossip posts (map §5.4).
// Guest can browse; liking / collecting needs login.

import SwiftUI

struct CommunityView: View {
    @EnvironmentObject private var api: HGHubAPI

    @State private var posts: [Post] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(posts) { post in
                    NavigationLink(destination: PostDetailView(postId: post.id)) {
                        PostRow(post: post)
                    }
                    .buttonStyle(.plain)
                }
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
            .padding()
        }
        .navigationTitle("社区")
        .refreshable { await load(page: 1) }
        .task { await load(page: 1) }
    }

    private func load(page targetPage: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let paged = try await api.posts(page: targetPage, size: 20)
            if targetPage == 1 {
                posts = paged.items
            } else {
                let known = Set(posts.map(\.id))
                posts += paged.items.filter { !known.contains($0.id) }
            }
            page = targetPage
            hasMore = paged.pagination.page < paged.pagination.pages
        } catch {
            if targetPage == 1 && posts.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PostRow: View {
    var post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(urlString: post.cover)
                .frame(width: 72, height: 96)
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if let time = post.publish_time ?? post.created_at {
                    Text(time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Text("热度 \(post.hot)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let counts = post.counts {
                        Text("评论 \(counts.comment)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("点赞 \(counts.like)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if !post.tags.isEmpty {
                    Text(post.tags.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
