import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([ActivitySession.self, LocationPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error.localizedDescription)")
        }
    }
}
