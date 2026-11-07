// HGHub iOS v1 — app entry.
// Guest browsing + playback, plus login-gated community (posts,
// comments, likes, collects, follows).
// This is a third-party client for the Huangguo site, not an official
// app. Personal, noncommercial use only — see LICENSE (PolyForm
// Noncommercial 1.0.0) and the About page in the My tab.

import SwiftUI

@main
struct HGHubApp: App {
    @StateObject private var edge = EdgeClient()
    @StateObject private var history = HistoryStore()
    @StateObject private var api: HGHubAPI
    @StateObject private var auth: AuthStore

    init() {
        let edge = EdgeClient()
        _edge = StateObject(wrappedValue: edge)
        _history = StateObject(wrappedValue: HistoryStore())
        let api = HGHubAPI(edge: edge)
        _api = StateObject(wrappedValue: api)
        _auth = StateObject(wrappedValue: AuthStore(edge: edge, api: api))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(edge)
                .environmentObject(api)
                .environmentObject(history)
                .environmentObject(auth)
        }
    }
}
