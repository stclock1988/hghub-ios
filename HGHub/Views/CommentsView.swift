// HGHub iOS — Video comments (map §5.5).
// Reading is guest; sending needs login. Replies are supported
// (reply_id); the comment-replies endpoint is documented-but-
// unimplemented upstream, so replies are shown inline from
// `reply_list` instead of being fetched separately.

import SwiftUI

struct CommentsView: View {
    @EnvironmentObject private var api: HGHubAPI
    @EnvironmentObject private var auth: AuthStore

    var videoId: Int
    var ep: Int

    @State private var comments: [Comment] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var draft = ""
    @State private var replyTarget: Comment?
    @State private var isSending = false
    @State private var sendError: String?
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment) {
                                replyTarget = comment
                            }
                            if let replies = comment.reply_list, !replies.isEmpty {
                                ForEach(replies) { reply in
                                    CommentRow(comment: reply, isReply: true) {
                                        replyTarget = reply
                                    }
                                    .padding(.leading, 32)
                                }
                            }
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
                        } else if comments.isEmpty {
                            Text("还没有评论")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding()
                }
                Divider()
                sendBox
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load(page: 1) }
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }

    private var sendBox: some View {
        HStack(spacing: 8) {
            if let replyTarget {
                Button {
                    self.replyTarget = nil
                } label: {
                    Label("回复 @\(replyTarget.nickname)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
            }
            TextField(
                replyTarget.map { "回复 @\($0.nickname)" }
                    ?? (auth.isLoggedIn ? "写评论…" : "登录后发评论"),
                text: $draft
            )
            .textFieldStyle(.roundedBorder)
            .disabled(isSending)
            Button("发送") {
                Task { await send() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding()
        .alert("发送失败", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("好") { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    private func load(page targetPage: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let paged = try await api.videoComments(id: videoId, ep: ep, page: targetPage, size: 12)
            if targetPage == 1 {
                comments = paged.items
            } else {
                let known = Set(comments.map(\.id))
                comments += paged.items.filter { !known.contains($0.id) }
            }
            page = targetPage
            hasMore = paged.pagination.page < paged.pagination.pages
        } catch {
            if targetPage == 1 && comments.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard auth.isLoggedIn else { showLogin = true; return }
        isSending = true
        defer { isSending = false }
        do {
            try await api.sendVideoComment(id: videoId, ep: ep, text: text, replyId: replyTarget?.id)
            draft = ""
            replyTarget = nil
            await load(page: 1)
        } catch {
            sendError = error.localizedDescription
        }
    }
}

struct CommentRow: View {
    var comment: Comment
    var isReply = false
    /// Nil hides the reply button (post comments have no send
    /// endpoint, so there is nothing to reply with).
    var onReply: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: comment.avatar_color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(comment.nickname.prefix(1)))
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
                Text(comment.nickname)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if comment.is_pinned == true {
                    Text("置顶")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
                Spacer()
                Text(comment.time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(comment.displayText)
                .font(.subheadline)
            HStack(spacing: 12) {
                if comment.like_count > 0 {
                    Label("\(comment.like_count)", systemImage: "heart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !isReply, let onReply {
                    Button("回复", action: onReply)
                        .font(.caption)
                }
                if !comment.ip_region.isNilOrEmpty {
                    Text(comment.ip_region ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private extension String? {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

private extension Color {
    /// A hex color like "#D0567F" (avatar_color). Falls back to gray.
    init(hex: String?) {
        let h = (hex ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
