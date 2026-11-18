import SwiftUI

@main
struct KomaApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var settings = AppSettings()

    init() {
        ImagePipelineConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(env)
                .environmentObject(settings)
                .onOpenURL { url in
                    if url.isFileURL {
                        env.importAndReport([url])
                    }
                }
        }
    }
}
