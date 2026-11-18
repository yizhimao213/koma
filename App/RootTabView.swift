import SwiftUI
import UIKit
import Combine

struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var tabBar = TabBarVisibility()
    @State private var selection: AppTab = .library

    init() {
        // The system bar is replaced by FloatingTabBar; this guards against it reappearing on push.
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        TabView(selection: $selection) {
            page(.library) { LibraryView(env: env) }
            page(.discover) { BrowseView() }
            page(.history) { HistoryView(env: env) }
            page(.downloads) { DownloadsView() }
            page(.settings) { SettingsView() }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection)
                .offset(y: tabBar.isHidden ? 140 : 0)
                .opacity(tabBar.isHidden ? 0 : 1)
                .allowsHitTesting(!tabBar.isHidden)
                .accessibilityHidden(tabBar.isHidden)
                .animation(Theme.spring, value: tabBar.isHidden)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            tabBar.setKeyboardVisible(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            tabBar.setKeyboardVisible(false)
        }
        .environmentObject(tabBar)
        .tint(settings.accentColor)
        .environment(\.accentColor, settings.accentColor)
        .preferredColorScheme(settings.appearanceOption.colorScheme)
        .overlay { ToastHost(center: env.toast) }
    }

    private func page<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabBar.contentInset)
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(tab)
    }
}
