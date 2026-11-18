import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("书架")
                .tabItem { Label("书架", systemImage: "books.vertical") }
            Text("发现")
                .tabItem { Label("发现", systemImage: "safari") }
            Text("历史")
                .tabItem { Label("历史", systemImage: "clock") }
            Text("下载")
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            Text("设置")
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
