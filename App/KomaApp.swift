import SwiftUI

@main
struct KomaApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(env)
                .onOpenURL { url in
                    if url.isFileURL {
                        env.importAndReport([url])
                    }
                }
        }
    }
}
