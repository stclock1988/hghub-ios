// HGHub iOS — Auth: login / register / me / logout (map §4).
// Token is stored in the Keychain (the original client kept it as
// plain JSON; the port uses Keychain instead). The token lasts ~7
// days; there is no refresh endpoint. On 401 the session is cleared
// and the user is prompted to log in again (the original does not
// do this; the port must, map §8).

import Foundation
import Security

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: MeUser?
    @Published private(set) var isLoggedIn = false

    private let edge: EdgeClient
    private let api: HGHubAPI

    private static let service = "hghub-ios"
    private static let account = "token"

    init(edge: EdgeClient, api: HGHubAPI) {
        self.edge = edge
        self.api = api
        if let token = Self.loadToken() {
            edge.token = token
            isLoggedIn = true
            Task { await refreshMe() }
        }
    }

    // MARK: - Token (Keychain)

    private static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) != errSecSuccess {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Session

    /// Validate the restored token and load the user + interactions.
    /// A 401 means the token expired: clear the session. A network
    /// error leaves the token in place; the user just stays unknown.
    func refreshMe() async {
        do {
            user = try await api.me()
        } catch {
            if case HGHubError.unauthorized = error {
                clearSession()
            }
        }
    }

    func login(username: String, password: String) async throws {
        let resp = try await api.login(username: username, password: password)
        applySession(token: resp.token)
        await refreshMe()
    }

    func register(username: String, password: String, confirmPassword: String, email: String?) async throws {
        let resp = try await api.register(username: username, password: password, confirmPassword: confirmPassword, email: email)
        applySession(token: resp.token)
        await refreshMe()
    }

    /// The server result is ignored; the local session is cleared
    /// either way (map §4).
    func logout() async {
        try? await api.logout()
        clearSession()
    }

    /// Clear the local session (expired token, or logout).
    func clearSession() {
        Self.deleteToken()
        edge.token = nil
        user = nil
        isLoggedIn = false
    }

    private func applySession(token: String) {
        Self.saveToken(token)
        edge.token = token
        isLoggedIn = true
    }

    /// Record a like / collect toggle locally so the me() snapshot
    /// stays consistent until the next refreshMe() (the player
    /// re-reads it whenever the episode changes).
    func noteVideoLiked(videoId: Int, ep: Int, on: Bool) {
        guard var me = user else { return }
        if on {
            if !me.interactions.like_video_episodes.contains(where: { $0.video_id == videoId && $0.ep == ep }) {
                me.interactions.like_video_episodes.append(LikedEpisode(video_id: videoId, ep: ep))
            }
        } else {
            me.interactions.like_video_episodes.removeAll { $0.video_id == videoId && $0.ep == ep }
        }
        user = me
    }

    func noteVideoCollected(videoId: Int, on: Bool) {
        guard var me = user else { return }
        if on {
            if !me.interactions.favorite_video_ids.contains(videoId) {
                me.interactions.favorite_video_ids.append(videoId)
            }
        } else {
            me.interactions.favorite_video_ids.removeAll { $0 == videoId }
        }
        user = me
    }
}
