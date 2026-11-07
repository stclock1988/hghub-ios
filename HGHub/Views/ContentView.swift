// HGHub iOS v1 — tab root.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("首页", systemImage: "house") }

            NavigationStack {
                CategoryView()
            }
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }

            NavigationStack {
                CommunityView()
            }
            .tabItem { Label("社区", systemImage: "newspaper") }

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            NavigationStack {
                MyView()
            }
            .tabItem { Label("我的", systemImage: "person") }
        }
    }
}
