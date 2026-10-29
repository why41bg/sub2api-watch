import SwiftUI

@main
@MainActor
struct Sub2APIWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(WatchStyle.green)
                .task(id: scenePhase) {
                    if scenePhase == .active { await store.refresh() }
                }
        }
    }
}
