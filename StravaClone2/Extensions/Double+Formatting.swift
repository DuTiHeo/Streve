import Foundation

extension Double {
    var kilometersText: String {
        String(format: "%.2f km", self / 1000)
    }

    var metersText: String {
        String(format: "%.0f m", self)
    }

    var paceText: String {
        guard isFinite, self > 0 else { return "--:--" }
        let roundedSeconds = Int(rounded())
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }
}

extension TimeInterval {
    var shortClockText: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    var longClockText: String {
        let totalSeconds = max(0, Int(self))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }
}
