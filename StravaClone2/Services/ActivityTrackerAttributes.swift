import ActivityKit
import Foundation

struct ActivityTrackerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var distanceMeters: Double
        var paceSecondsPerKm: Double
        var activityType: String
    }

    var sessionID: String
}

extension ActivityTrackerAttributes.ContentState {
    var formattedElapsed: String {
        TimeInterval(elapsedSeconds).longClockText
    }

    var formattedDistance: String {
        distanceMeters.kilometersText
    }

    var formattedPace: String {
        "\(paceSecondsPerKm.paceText)/km"
    }
}
