import SwiftUI
import Nuke
import NukeUI

/// Cover thumbnail at a fixed 2:3 aspect ratio. `size` is the decode target in points.
struct CoverImageView: View {
    let url: URL?
    let size: CGSize

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil || url == nil {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .processors([.resize(size: size)])
                .animation(.easeIn(duration: 0.15))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
    }
}
