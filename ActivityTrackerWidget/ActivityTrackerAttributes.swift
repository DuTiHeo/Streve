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
        let totalSeconds = max(0, elapsedSeconds)
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }

    var formattedDistance: String {
        String(format: "%.2f km", distanceMeters / 1000)
    }

    var formattedPace: String {
        guard paceSecondsPerKm.isFinite, paceSecondsPerKm > 0 else { return "--:--/km" }
        let seconds = Int(paceSecondsPerKm.rounded())
        return String(format: "%d:%02d/km", seconds / 60, seconds % 60)
    }
}
