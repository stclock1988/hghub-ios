// HGHub iOS — Post detail (map §5.4).
// Content is HTML with an <img> gallery: we strip tags for the
// text and show the images through CoverImage (which already
// handles the CDN's encrypted covers). Post comments are read-only
// — upstream has no send endpoint for post comments, only for
// video comments. If the post has a video_url, it plays inline.

import SwiftUI
import AVKit

struct PostDetailView: View {
    @EnvironmentObject private var api: HGHubAPI
    @EnvironmentObject private var edge: EdgeClient
    @EnvironmentObject private var auth: AuthStore

    var postId: Int

    @State private var post: Post?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var liked = false
    @State private var collected = false
    @State private var showLogin = false
    @State private var showVideo = false
    @State private var comments: [Comment] = []
    @State private var commentPage = 1
    @State private var commentHasMore = true
    @State private var commentLoading = false
    @State private var commentError: String?

    var body: some View {
        ScrollView {
            if let post {
                VStack(alignment: .leading, spacing: 16) {
                    Text(post.title)
                        .font(.headline)
                    HStack(spacing: 8) {
                        if let author = post.author {
                            Text(author.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let time = post.publish_time ?? post.created_at {
                            Text(time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let counts = post.counts {
                            Text("热度 \(counts.hot ?? post.hot)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 16) {
                        Button {
                            Task { await toggleLike() }
                        } label: {
                            Label(liked ? "已点赞" : "点赞", systemImage: liked ? "heart.fill" : "heart")
                        }
                        Button {
                            Task { await toggleCollect() }
                        } label: {
                            Label(collected ? "已收藏" : "收藏", systemImage: collected ? "bookmark.fill" : "bookmark")
                        }
                        if let counts = post.counts {
                            Label("\(counts.comment)", systemImage: "text.bubble")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let videoURL = post.video_url, !videoURL.isEmpty {
                        Button {
                            showVideo = true
                        } label: {
                            ZStack {
                                CoverImage(urlString: post.cover)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .cornerRadius(8)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    let parsed = parseContent(post.content ?? "", base: edge.base)
                    if !parsed.text.isEmpty {
                        Text(parsed.text)
                            .font(.subheadline)
                    }
                    ForEach(parsed.images, id: \.self) { url in
                        CoverImage(urlString: url)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .cornerRadius(8)
                    }
                    if !post.tags.isEmpty {
                        Text(post.tags.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    Text("评论")
                        .font(.headline)
                    if commentLoading && comments.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let commentError, comments.isEmpty {
                        ErrorStateView(message: commentError) { Task { await loadComments(page: 1) } }
                    } else if comments.isEmpty {
                        Text("还没有评论")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment)
                            if let replies = comment.reply_list, !replies.isEmpty {
                                ForEach(replies) { reply in
                                    CommentRow(comment: reply, isReply: true)
                                        .padding(.leading, 32)
                                }
                            }
                        }
                        if commentHasMore {
                            Button("加载更多评论") { Task { await loadComments(page: commentPage + 1) } }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            } else if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
            }
        }
        .navigationTitle("帖子")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showLogin) { LoginView() }
        .fullScreenCover(isPresented: $showVideo) {
            if let url = post?.video_url {
                PostVideoView(urlString: url)
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let p = try await api.post(id: postId)
            post = p
            liked = p.interaction?.liked ?? false
            collected = p.interaction?.collected ?? false
            await loadComments(page: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadComments(page targetPage: Int) async {
        guard !commentLoading else { return }
        commentLoading = true
        commentError = nil
        defer { commentLoading = false }
        do {
            let paged = try await api.postComments(id: postId, page: targetPage, size: 12)
            if targetPage == 1 {
                comments = paged.items
            } else {
                let known = Set(comments.map(\.id))
                comments += paged.items.filter { !known.contains($0.id) }
            }
            commentPage = targetPage
            commentHasMore = paged.pagination.page < paged.pagination.pages
        } catch {
            if targetPage == 1 && comments.isEmpty {
                commentError = error.localizedDescription
            }
        }
    }

    private func toggleLike() async {
        guard auth.isLoggedIn else { showLogin = true; return }
        let next = !liked
        liked = next
        do {
            try await api.setPostLike(id: postId, on: next)
        } catch {
            liked = !next
        }
    }

    private func toggleCollect() async {
        guard auth.isLoggedIn else { showLogin = true; return }
        let next = !collected
        collected = next
        do {
            try await api.setPostCollect(id: postId, on: next)
        } catch {
            collected = !next
        }
    }
}

/// Parse post HTML content into plain text + image URLs. Scripts,
/// styles, iframes, forms and event handlers never survive: only
/// text and image sources are extracted. Image sources prefer
/// data-src / data-original / data-lazy-src over src (the original
/// frontend does the same, map §5.4); relative URLs resolve against
/// the current line's base.
private func parseContent(_ html: String, base: String) -> (text: String, images: [String]) {
    var images: [String] = []
    if let imgRegex = try? NSRegularExpression(pattern: #"<img[^>]*>"#, options: [.caseInsensitive]) {
        let ns = html as NSString
        for m in imgRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            guard var src = extractImageSrc(tag), !src.isEmpty else { continue }
            let lower = src.lowercased()
            if lower.contains("placeholder") || lower.contains("cover-placeh") { continue }
            if src.hasPrefix("/") { src = base + src }
            if !images.contains(src) { images.append(src) }
        }
    }
    var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    text = text
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")
    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (text, images)
}

private func extractImageSrc(_ tag: String) -> String? {
    for name in ["data-src", "data-original", "data-lazy-src", "src"] {
        let pattern = name + #"=["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
           let r = Range(m.range(at: 1), in: tag) {
            return String(tag[r])
        }
    }
    return nil
}

/// A plain video player for a post's video_url (a direct m3u8 URL).
private struct PostVideoView: View {
    @Environment(\.dismiss) private var dismiss
    var urlString: String

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                HGPlayerViewController(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            Button("关闭") { dismiss() }
                .padding()
        }
        .task {
            if player == nil, let url = URL(string: urlString) {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
