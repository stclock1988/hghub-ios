// HGHub iOS v1 — local watch history (map §9).
// Local only: the server's history count is never written back.
// Cap 80 entries, newest first; each entry keeps episode + seconds
// so playback can resume.

import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: Int { videoId }
    var videoId: Int
    var title: String
    var cover: String
    var ep: Int
    var seconds: Double
    var duration: Double
    var at: Date
}

final class HistoryStore: ObservableObject {
    private static let key = "hghub.history.v1"
    private static let cap = 80

    @Published private(set) var entries: [HistoryEntry] = []

    init() {
        load()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { entries = []; return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func entry(for videoId: Int) -> HistoryEntry? {
        entries.first { $0.videoId == videoId }
    }

    func record(videoId: Int, title: String, cover: String, ep: Int, seconds: Double, duration: Double) {
        guard seconds > 1 || duration > 0 else { return }
        let entry = HistoryEntry(
            videoId: videoId, title: title, cover: cover,
            ep: ep, seconds: seconds, duration: duration, at: Date()
        )
        entries.removeAll { $0.videoId == videoId }
        entries.insert(entry, at: 0)
        if entries.count > Self.cap {
            entries = Array(entries.prefix(Self.cap))
        }
        save()
    }

    func remove(videoId: Int) {
        entries.removeAll { $0.videoId == videoId }
        save()
    }

    func clear() {
        entries = []
        save()
    }
}
