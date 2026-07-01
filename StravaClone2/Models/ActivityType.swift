import Foundation

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case run = "Run"
    case walk = "Walk"
    case ride = "Ride"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .run:
            return "figure.run"
        case .walk:
            return "figure.walk"
        case .ride:
            return "figure.outdoor.cycle"
        }
    }

    var liveActivityLabel: String {
        switch self {
        case .run:
            return "Running"
        case .walk:
            return "Walking"
        case .ride:
            return "Riding"
        }
    }
}
