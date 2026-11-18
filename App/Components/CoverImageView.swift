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
                        FadeInImage(image: image)
                    } else if state.error != nil || url == nil {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .processors([.resize(size: size)])
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
    }
}

/// Fades the loaded image in over 0.15 s.
private struct FadeInImage: View {
    let image: Image
    @State private var visible = false

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: 0.15)) { visible = true } }
    }
}
