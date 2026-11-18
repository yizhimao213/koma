import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?
    private var token = 0

    func show(_ text: String) {
        token += 1
        let current = token
        message = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.token == current else { return }
            self.message = nil
        }
    }
}

struct ToastHost: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let message = center.message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: center.message)
        .allowsHitTesting(false)
    }
}
