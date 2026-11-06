// HGHub iOS v1 — API models.
// Shapes follow ~/workspace/hghub-reference/api-map.md §5.2.2 / §5.3
// exactly; no fields invented. Episode.status is typed but never used
// for gating — every listed episode is playable (map §8).

import Foundation

struct Author: Codable {
    var id: Int = 0
    var name: String = ""
    var avatar: String?
    var followers: Int?
}

struct VideoCard: Codable, Identifiable {
    var id: Int
    var title: String = ""
    var cover: String = ""
    var description: String?
    var tags: [String] = []
    var score: Double = 0
    var episode_count: Int = 0
    var total_episodes: Int = 0
    var duration: String?
    var hot: Int = 0
    var like_count: Int = 0
    var collect_count: Int = 0
    var comment_count: Int = 0
    var is_finished: Bool = false
    var is_original: Int = 0
    var created_at: String?
    var last_ep_at: Int?
    var new_at: Int?
    var author: Author?
    var preview_url: String?
}

struct Pagination: Codable {
    var page: Int = 1
    var pages: Int = 1
    var size: Int = 20
    var total: Int = 0
}

struct Paged<T: Codable>: Codable {
    var items: [T] = []
    var pagination: Pagination = Pagination()
}

struct Episode: Codable, Identifiable {
    var id: Int { ep_num }
    var ep_num: Int
    var title: String = ""
    var duration: Int = 0
    /// Typed by the upstream API but never read anywhere in the
    /// original client; it is NOT a lock / paywall flag.
    var status: Int = 0
}

struct Counts: Codable {
    var collect: Int = 0
    var comment: Int = 0
    var hot: Int = 0
    var like: Int = 0
}

struct TagLink: Codable {
    var name: String = ""
    var url: String = ""
}

struct DetailInteraction: Codable {
    var collected: Bool = false
    var liked: Bool = false
    var liked_ep: Int?
}

struct Detail: Codable {
    var id: Int
    var title: String = ""
    var description: String = ""
    var cover: String = ""
    var tags: [String] = []
    var tag_links: [TagLink]?
    var score: Double = 0
    var episode_count: Int = 0
    var total_episodes: Int = 0
    var episodes: [Episode] = []
    var counts: Counts = Counts()
    var author: Author?
    var interaction: DetailInteraction?
    var video_url: String?
    var video_url_hevc: String?
    var is_finished: Bool = false
    var is_original: Int = 0
    var video_type: Int?
    /// Live API returns a STRING here ("207"), not a number — the
    /// map's TS type said number, but the real response (verified
    /// 2026-11-06 against /api/videos/12) is a string. Decoding it
    /// as Int failed every detail request, so every drama opened
    /// blank. Same as VideoCard.duration, which is already a string.
    var duration: String?
    var created_at: String?
}

struct PlayInfo: Codable {
    var id: Int = 0
    var ep_num: Int = 0
    var duration: Int = 0
    var title: String = ""
    /// HLS m3u8 URL. Its auth_key is time-limited (~1 hour): fetch
    /// fresh per episode, never cache this URL long-term.
    var video_url: String = ""
    var video_url_hevc: String?
}

struct RankMetrics: Codable {
    var collect: Int = 0
    var comment: Int = 0
    var like: Int = 0
    var play: Int = 0
}

struct RankItem: Codable, Identifiable {
    var id: Int { video_id }
    var rank: Int = 0
    var video_id: Int = 0
    var title: String = ""
    var cover: String = ""
    var tags: [String] = []
    var score: Double = 0
    var cate_name: String?
    var episode_count: Int = 0
    var is_finished: Bool = false
    var metric_label: String?
    var metric_value: Double?
    var metrics: RankMetrics?
}

struct RankResponse: Codable {
    var type: String = "hot"
    var items: [RankItem] = []
}

struct SearchResponse: Codable {
    var engine: String?
    var keyword: String?
    var type: String?
    var items: [VideoCard] = []
    var pagination: Pagination = Pagination()
}

/// The four fixed video categories (map §5.2.1). Gossip posts are
/// out of v1 scope, so there is no posts category here.
enum HGHubCategory: String, CaseIterable, Identifiable {
    case aiDuanju = "ai-duanju"
    case aiManju = "ai-manju"
    case aiHuanlian = "ai-huanlian"
    case aiMogai = "ai-mogai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiDuanju: return "AI 成人短剧"
        case .aiManju: return "AI 成人漫剧"
        case .aiHuanlian: return "AI 换脸"
        case .aiMogai: return "AI 魔改"
        }
    }
}

/// Hot search tags shown on the search page (map §5.2).
let hghubHotTags = ["都市", "逆袭", "古风", "系统", "后宫", "校园", "仙侠", "职场", "大男主", "御姐", "脑洞", "奇幻"]
