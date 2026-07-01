import CoreLocation
import Foundation
import SwiftData

@Model
final class ActivitySession {
    var id: UUID
    var activityType: ActivityType
    var startTime: Date
    var endTime: Date?
    var totalDistance: Double
    var totalDuration: TimeInterval
    var elevationGain: Double

    @Relationship(deleteRule: .cascade)
    var locationPoints: [LocationPoint]

    var averagePace: Double {
        guard totalDistance > 0 else { return 0 }
        return totalDuration / (totalDistance / 1000)
    }

    var coordinates: [CLLocationCoordinate2D] {
        locationPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.coordinate)
    }

    init(type: ActivityType) {
        self.id = UUID()
        self.activityType = type
        self.startTime = Date()
        self.endTime = nil
        self.totalDistance = 0
        self.totalDuration = 0
        self.elevationGain = 0
        self.locationPoints = []
    }
}
