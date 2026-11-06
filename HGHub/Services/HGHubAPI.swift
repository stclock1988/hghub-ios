// HGHub iOS v1 — guest API only (map §5).
// No login/register, no likes/collects/comments/follows, no posts.
// Every call goes through the edge envelope; play is fetched FRESH
// per episode because the m3u8 auth_key expires in ~1 hour.

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
}
