import SwiftUI

@main
struct ChainScopeAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
                .task {
                    await model.bootstrap()
                }
        }
    }
}
