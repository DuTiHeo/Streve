import Combine
import Foundation
import SwiftData

final class HistoryViewModel: ObservableObject {
    @Published var sessions: [ActivitySession] = []

    @MainActor
    func loadSessions(context: ModelContext) {
        let descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        sessions = (try? context.fetch(descriptor)) ?? []
    }
}
