import SwiftData
import SwiftUI

@main
struct ActivityTrackerApp: App {
    @StateObject private var locationService = LocationManagerService.shared
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationService)
        }
        .modelContainer(persistenceController.container)
    }
}
