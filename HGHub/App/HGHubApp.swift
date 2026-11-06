// HGHub iOS v1 — app entry.
// Guest browsing + playback only: no login, no posts, no download.
// This is a third-party client for the Huangguo site, not an official
// app. Personal, noncommercial use only — see LICENSE (PolyForm
// Noncommercial 1.0.0) and the About page in the My tab.

import SwiftUI

@main
struct HGHubApp: App {
    @StateObject private var edge = EdgeClient()
    @StateObject private var history = HistoryStore()
    @StateObject private var api: HGHubAPI

    init() {
        let edge = EdgeClient()
        _edge = StateObject(wrappedValue: edge)
        _history = StateObject(wrappedValue: HistoryStore())
        _api = StateObject(wrappedValue: HGHubAPI(edge: edge))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(edge)
                .environmentObject(api)
                .environmentObject(history)
        }
    }
}
