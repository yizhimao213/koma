import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            LibraryView(library: env.library)
                .tabItem { Label("书架", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("发现", systemImage: "safari") }
            HistoryView(env: env)
                .tabItem { Label("历史", systemImage: "clock") }
            DownloadsView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(settings.accentColor)
        .environment(\.accentColor, settings.accentColor)
        .preferredColorScheme(settings.appearanceOption.colorScheme)
        .overlay { ToastHost(center: env.toast) }
    }
}
