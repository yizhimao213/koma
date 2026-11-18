import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            LibraryView(library: env.library)
                .tabItem { Label("书架", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("发现", systemImage: "safari") }
            Text("历史")
                .tabItem { Label("历史", systemImage: "clock") }
            Text("下载")
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            Text("设置")
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .overlay { ToastHost(center: env.toast) }
    }
}
