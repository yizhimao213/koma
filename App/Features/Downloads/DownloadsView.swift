import SwiftUI

struct DownloadsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(symbol: "arrow.down.circle", title: "下载功能即将上线", actionTitle: nil, action: nil)
                .navigationTitle("下载")
        }
    }
}
