// HGHub iOS v1 — API (map §5).
// Guest browsing + playback, plus login-gated community: posts,
// comments, likes, collects, follows. Every call goes through the
// edge envelope; play is fetched FRESH per episode because the
// m3u8 auth_key expires in ~1 hour.

import Foundation

final class HGHubAPI: ObservableObject {
    let edge: EdgeClient

    init(edge: EdgeClient) {
        self.edge = edge
    }

    // MARK: - Discovery

    func feed(page: Int, size: Int = 20) async throws -> Paged<VideoCard> {
        try await edge.edge(method: "GET", path: "/api/videos?page=\(page)&size=\(size)")
    }

    func category(_ cate: HGHubCategory, page: Int, size: Int = 20) async throws -> Paged<VideoCard> {
        try await edge.edge(method: "GET", path: "/api/videos/category/\(cate.rawValue)?page=\(page)&size=\(size)")
    }

    func ranks(kind: String) async throws -> RankResponse {
        let safe = ["recommend", "potential"].contains(kind) ? kind : "hot"
        return try await edge.edge(method: "GET", path: "/api/ranks/\(safe)")
    }

    func search(query: String, page: Int, size: Int = 20) async throws -> SearchResponse {
        // The param MUST be `q` — `keyword` returns
        // status:0, msg:"请输入搜索关键词" (map §5.2).
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)"),
        ]
        let qs = components.percentEncodedQuery ?? "q="
        return try await edge.edge(method: "GET", path: "/api/search?\(qs)")
    }

    // MARK: - Detail / play

    func video(id: Int) async throws -> Detail {
        try await edge.edge(method: "GET", path: "/api/videos/\(id)")
    }

    func play(id: Int, ep: Int) async throws -> PlayInfo {
        let info: PlayInfo = try await edge.edge(
            method: "GET",
            path: "/api/videos/\(id)/play?ep=\(ep)&page_texts=0"
        )
        guard !info.video_url.isEmpty else { throw HGHubError.noPlayURL }
        return info
    }

    // MARK: - Auth (019, map §4)

    func login(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        return try await edge.edge(method: "POST", path: "/api/account/loginByPassword", body: body)
    }

    func register(username: String, password: String, confirmPassword: String, email: String?) async throws -> AuthResponse {
        var dict: [String: String] = [
            "username": username,
            "password": password,
            "confirm_password": confirmPassword,
        ]
        if let email, !email.isEmpty { dict["email"] = email }
        let body = try JSONEncoder().encode(dict)
        return try await edge.edge(method: "POST", path: "/api/account/registerByPassword", body: body)
    }

    func me() async throws -> MeUser {
        try await edge.edge(method: "GET", path: "/api/account/me")
    }

    func logout() async throws {
        try await edge.action(method: "POST", path: "/api/account/logout")
    }

    // MARK: - Community (019, map §5.4 / §5.5)

    func posts(page: Int, size: Int = 20) async throws -> Paged<Post> {
        try await edge.edge(method: "GET", path: "/api/posts?page=\(page)&size=\(size)")
    }

    func post(id: Int) async throws -> Post {
        try await edge.edge(method: "GET", path: "/api/posts/\(id)")
    }

    func postComments(id: Int, page: Int, size: Int = 12) async throws -> CommentPage {
        try await edge.edge(method: "GET", path: "/api/posts/\(id)/comments?page=\(page)&size=\(size)")
    }

    func videoComments(id: Int, ep: Int, page: Int, size: Int = 12) async throws -> CommentPage {
        try await edge.edge(method: "GET", path: "/api/videos/\(id)/comments?ep=\(ep)&page=\(page)&size=\(size)")
    }

    /// Send a video comment. Replying (`replyId > 0`) uses a
    /// different path (no `?ep=`) and carries `reply_id` in the
    /// body — the path difference is load-bearing (map §5.5).
    /// There is no send endpoint for post comments upstream, so
    /// post comments are read-only.
    func sendVideoComment(id: Int, ep: Int, text: String, replyId: Int? = nil) async throws {
        let body = try JSONEncoder().encode(SendCommentBody(text: text, reply_id: replyId))
        if let replyId, replyId > 0 {
            try await edge.action(method: "POST", path: "/api/videos/\(id)/comments", body: body)
        } else {
            try await edge.action(method: "POST", path: "/api/videos/\(id)/comments?ep=\(ep)", body: body)
        }
    }

    /// Like is per (video, episode): `ep` must be in the query,
    /// not the body (map §5.5).
    func setVideoLike(id: Int, ep: Int, on: Bool) async throws {
        try await edge.action(method: on ? "POST" : "DELETE", path: "/api/videos/\(id)/like?ep=\(ep)")
    }

    func setVideoCollect(id: Int, on: Bool) async throws {
        try await edge.action(method: on ? "POST" : "DELETE", path: "/api/videos/\(id)/collect")
    }

    func setFollow(uid: Int, on: Bool) async throws {
        try await edge.action(method: on ? "POST" : "DELETE", path: "/api/users/\(uid)/follow")
    }

    func setPostLike(id: Int, on: Bool) async throws {
        try await edge.action(method: on ? "POST" : "DELETE", path: "/api/posts/\(id)/like")
    }

    func setPostCollect(id: Int, on: Bool) async throws {
        try await edge.action(method: on ? "POST" : "DELETE", path: "/api/posts/\(id)/collect")
    }
}
