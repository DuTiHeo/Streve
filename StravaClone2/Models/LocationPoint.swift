import CoreLocation
import Foundation
import SwiftData

@Model
final class LocationPoint {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var timestamp: Date
    var accuracy: Double

    init(latitude: Double, longitude: Double, altitude: Double, speed: Double, timestamp: Date, accuracy: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.timestamp = timestamp
        self.accuracy = accuracy
    }

    convenience init(from location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            speed: location.speed,
            timestamp: location.timestamp,
            accuracy: location.horizontalAccuracy
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
